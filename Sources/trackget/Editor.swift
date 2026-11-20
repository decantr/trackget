import AVFoundation
import Foundation
import Observation

struct EditPart: Identifiable {
	let id = UUID()
	var include = true
	var title: String
	var artist: String
}

enum Marker: Equatable {
	case playhead
	case start
	case end
	case cut(Int)
}

@MainActor
@Observable
final class Editor {
	static let peaks_per_second = 50.0
	static let shortest_view = 2.0

	var file: URL?
	var duration = 0.0
	var peaks: [Float] = []
	var title = ""
	var artist = ""
	var album = ""
	var album_artist = ""
	var trim_start = 0.0
	var trim_end = 0.0
	var cuts: [Double] = []
	var parts: [EditPart] = []
	var playhead = 0.0
	var view_start = 0.0
	var view_length = 0.0
	@ObservationIgnored private var last_manual_view = Date.distantPast
	var playing = false
	var busy = false
	var status = ""
	var saved_file: URL?

	@ObservationIgnored private var player: AVAudioPlayer?
	@ObservationIgnored private var preview_file: URL?
	@ObservationIgnored private var ticker: Task<Void, Never>?

	var boundaries: [Double] { [trim_start] + cuts + [trim_end] }

	var is_split: Bool { parts.count > 1 }

	// Split parts belong to the release that Title and Artist name
	var parts_album: String { album.isEmpty ? title : album }
	var parts_album_artist: String { album_artist.isEmpty ? artist : album_artist }

	var can_save: Bool {
		guard file != nil, !busy else {
			return false
		}
		if is_split {
			let included = parts.filter(\.include)
			return !included.isEmpty && included.allSatisfy { !$0.title.isEmpty && !$0.artist.isEmpty }
		}
		return !title.isEmpty && !artist.isEmpty
	}

	func open(_ url: URL) async {
		stop()
		removePreview()
		busy = true
		status = "Opening \(url.lastPathComponent)…"
		saved_file = nil
		do {
			let info = try await readAudioInfo(url)
			file = url
			duration = info.duration
			title = info.tags["title"] ?? url.deletingPathExtension().lastPathComponent
			artist = info.tags["artist"] ?? ""
			album = info.tags["album"] ?? ""
			album_artist = info.tags["album_artist"] ?? ""
			trim_start = 0
			trim_end = duration
			view_start = 0
			view_length = duration
			cuts = []
			parts = [EditPart(title: title, artist: artist)]
			playhead = 0
			peaks = []
			player = try await makePlayer(url)
			peaks = try await loadPeaks(url, duration: duration, count: max(1, Int(duration * Self.peaks_per_second)))
			status = "\(url.lastPathComponent), \(clockTime(duration))"
		} catch {
			status = error.localizedDescription
		}
		busy = false
	}

	// AVAudioPlayer can't read Ogg, so opus files get a temporary wav copy for listening only
	private func makePlayer(_ url: URL) async throws -> AVAudioPlayer {
		if let player = try? AVAudioPlayer(contentsOf: url) {
			return player
		}
		let preview = FileManager.default.temporaryDirectory.appendingPathComponent("trackget-preview-\(UUID().uuidString).wav")
		let status = try await runProcess(Tools.path("ffmpeg"), ["-nostdin", "-v", "error", "-i", url.path, "-map", "0:a:0", preview.path])
		if status != 0 {
			throw ShellError(message: "Could not prepare \(url.lastPathComponent) for playback")
		}
		preview_file = preview
		return try AVAudioPlayer(contentsOf: preview)
	}

	private func removePreview() {
		if let preview_file {
			try? FileManager.default.removeItem(at: preview_file)
		}
		preview_file = nil
	}

	func close() {
		stop()
		removePreview()
		player = nil
	}

	func togglePlay() {
		guard let player else {
			return
		}
		if playing {
			stop()
			return
		}
		player.currentTime = playhead >= trim_end ? trim_start : playhead
		player.play()
		playing = true
		ticker = Task { [weak self] in
			while let self, self.playing, let player = self.player {
				self.playhead = player.currentTime
				self.follow()
				if !player.isPlaying || player.currentTime >= self.trim_end {
					self.stop()
					break
				}
				try? await Task.sleep(for: .milliseconds(30))
			}
		}
	}

	func stop() {
		player?.pause()
		playing = false
		ticker?.cancel()
		ticker = nil
	}

	var is_zoomed: Bool { view_length < duration }

	// Keeps the time under the pointer in the same place on screen
	func zoom(by factor: Double, around time: Double) {
		guard duration > 0 else {
			return
		}
		let length = min(max(view_length / factor, min(Self.shortest_view, duration)), duration)
		let fraction = view_length > 0 ? (time - view_start) / view_length : 0.5
		view_length = length
		pan(to: time - fraction * length)
	}

	func zoomAroundPlayhead(by factor: Double) {
		let visible = playhead >= view_start && playhead <= view_start + view_length
		zoom(by: factor, around: visible ? playhead : view_start + view_length / 2)
	}

	func pan(to start: Double) {
		last_manual_view = .now
		view_start = clampedStart(start)
	}

	private func clampedStart(_ start: Double) -> Double {
		min(max(start, 0), max(0, duration - view_length))
	}

	// Brings the playhead back into view during playback, unless the view moved by hand a moment ago
	private func follow() {
		let visible = playhead >= view_start && playhead <= view_start + view_length
		if !visible && Date.now.timeIntervalSince(last_manual_view) > 1.5 {
			view_start = clampedStart(playhead - view_length * 0.1)
		}
	}

	func seek(_ time: Double) {
		playhead = min(max(time, 0), duration)
		player?.currentTime = playhead
	}

	func markerTime(_ marker: Marker) -> Double {
		switch marker {
		case .playhead: playhead
		case .start: trim_start
		case .end: trim_end
		case .cut(let index): cuts.indices.contains(index) ? cuts[index] : 0
		}
	}

	// Markers keep their order, with at least half a second between neighbours
	func move(_ marker: Marker, to time: Double) {
		let gap = 0.5
		let points = boundaries
		switch marker {
		case .playhead:
			seek(time)
		case .start:
			trim_start = min(max(time, 0), points[1] - gap)
		case .end:
			trim_end = max(min(time, duration), points[points.count - 2] + gap)
		case .cut(let index):
			guard cuts.indices.contains(index) else {
				return
			}
			cuts[index] = min(max(time, points[index] + gap), points[index + 2] - gap)
		}
	}

	func setStart() {
		move(.start, to: playhead)
	}

	func setEnd() {
		move(.end, to: playhead)
	}

	var can_split: Bool {
		playhead > trim_start + 0.5 && playhead < trim_end - 0.5 && !cuts.contains { abs($0 - playhead) < 0.5 }
	}

	func split() {
		guard can_split else {
			return
		}
		let index = cuts.firstIndex { $0 > playhead } ?? cuts.count
		cuts.insert(playhead, at: index)
		let names = splitTitle(title)
		if parts.count == 1 && names.count > 1 {
			parts[0].title = names[0]
		}
		let new_title = index + 1 < names.count && parts.count < names.count ? names[index + 1] : ""
		parts.insert(EditPart(title: new_title, artist: artist), at: index + 1)
	}

	// Removing the cut before a part merges that part into the one before it
	func merge(_ part_index: Int) {
		cuts.remove(at: part_index - 1)
		parts.remove(at: part_index)
		if parts.count == 1 {
			parts[0].title = title
		}
	}

	func save(to folder: URL) async {
		guard let file else {
			return
		}
		stop()
		busy = true
		saved_file = nil
		do {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			let points = boundaries
			let included = parts.indices.filter { parts[$0].include }
			let ext = file.pathExtension
			for (number, index) in included.enumerated() {
				let part = parts[index]
				status = "Saving \(number + 1) of \(included.count)…"
				let name = is_split ? "\(part.artist) - \(part.title)" : "\(artist) - \(title)"
				let target = uniqueFile(in: folder, name: name, ext: ext)
				let end = points[index + 1] < duration - 0.01 ? points[index + 1] : nil
				let range: (Double, Double?)? = points[index] > 0 || end != nil ? (points[index], end) : nil
				try await writeAudio(from: file, to: target, tags: tags(for: part, number: number + 1, of: included.count, ext: ext), range: range, log: { _ in })
				saved_file = target
			}
			status = included.count == 1 ? "Saved \(saved_file?.lastPathComponent ?? "")" : "Saved \(included.count) tracks"
		} catch {
			status = error.localizedDescription
		}
		busy = false
	}

	private func tags(for part: EditPart, number: Int, of count: Int, ext: String) -> [(String, String)] {
		guard is_split else {
			return [("title", title), ("artist", artist), ("album", album), ("album_artist", album_artist)]
		}
		var tags = [
			("title", part.title),
			("artist", part.artist),
			("album", parts_album),
			("album_artist", parts_album_artist),
			("track", "\(number)/\(count)"),
		]
		// The source's ARTISTS lists every artist in the whole file, which is wrong for one part
		if ext != "m4a" {
			tags.append(("ARTISTS", ""))
		}
		return tags
	}
}

func preciseTime(_ seconds: Double) -> String {
	let minutes = Int(seconds) / 60
	return String(format: "%d:%04.1f", minutes, seconds - Double(minutes * 60))
}
