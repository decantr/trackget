import AppKit
import Foundation
import Observation

enum AudioFormat: String, CaseIterable, Identifiable {
	case mp3, m4a, flac, opus
	var id: String { rawValue }
}

@MainActor
@Observable
final class Model {
	var url = "" {
		didSet {
			if saved_file != nil && url != oldValue {
				clearTrack()
			}
		}
	}
	var title = ""
	var artist = ""
	var artists = ""
	var album = ""
	var album_artist = ""
	var year = ""
	var genre = ""
	var track_number = ""
	var parts: [Part] = []
	var split_parts = false
	var chapter_count = 0

	var busy = false
	var progress: Double?
	var status = ""
	var log = ""
	var saved_file: URL?
	var installed_version = ""
	var latest_version: String?
	var app_update: AppRelease?

	var update_available: Bool {
		guard let latest_version, !installed_version.isEmpty else {
			return false
		}
		return installed_version.compare(latest_version, options: .numeric) == .orderedAscending
	}

	var can_download: Bool {
		guard !busy, !trimmed(url).isEmpty, !trimmed(title).isEmpty, !trimmed(artist).isEmpty else {
			return false
		}
		if split_parts {
			let included = parts.filter(\.include)
			return parts_valid && !included.isEmpty && included.allSatisfy { !trimmed($0.title).isEmpty && !trimmed($0.artist).isEmpty }
		}
		return true
	}

	var parts_valid: Bool {
		let starts = parts.compactMap(\.start)
		return starts.count == parts.count && zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 }
	}

	// Split parts belong to the release that the main Title and Artist name
	var parts_album: String { trimmed(album).isEmpty ? trimmed(title) : trimmed(album) }
	var parts_album_artist: String { trimmed(album_artist).isEmpty ? trimmed(artist) : trimmed(album_artist) }

	func setSplit(_ is_on: Bool) {
		split_parts = is_on
		guard is_on, parts.isEmpty else {
			return
		}
		var names = splitTitle(title)
		if names.count < 2 {
			names = [title, ""]
		}
		let featured = artists.split(separator: ";").map { trimmed(String($0)) }.dropFirst()
		parts = names.enumerated().map { index, name in
			Part(
				start_text: index == 0 ? "0:00" : "",
				title: name,
				artist: artist,
				featured: name.contains(/(?i)\bfeat\./) ? Array(featured) : []
			)
		}
	}

	func addPart() {
		parts.append(Part(start_text: "", title: "", artist: artist))
	}

	func removePart(_ id: Part.ID) {
		parts.removeAll { $0.id == id }
	}

	private func clearTrack() {
		title = ""
		artist = ""
		artists = ""
		album = ""
		album_artist = ""
		year = ""
		genre = ""
		track_number = ""
		parts = []
		split_parts = false
		chapter_count = 0
		saved_file = nil
		status = ""
	}

	func prepareTools() async {
		let missing = Tools.missing
		guard !missing.isEmpty else {
			return
		}
		await work("Installing tools") {
			for tool in missing {
				self.status = "Installing \(tool.name)…"
				if tool.name == Tools.ytdlp.name {
					try await Tools.install(Tools.ytDlpRelease(Tools.latestYtDlpVersion()))
				} else {
					try await Tools.install(tool)
				}
			}
			self.status = "Tools installed"
		}
	}

	func checkAppUpdate() async {
		do {
			app_update = try await Updater.latestRelease()
			if let app_update {
				appendLog("== TrackGet \(app_update.version) is available (installed \(Updater.current_version))")
			}
		} catch {
			appendLog("!! TrackGet update check failed: \(error.localizedDescription)")
		}
	}

	func installAppUpdate() async {
		guard let app_update else {
			return
		}
		var staged = false
		await work("Updating TrackGet to \(app_update.version)") {
			try await Updater.stage(app_update, log: self.appendLog)
			staged = true
		}
		if staged {
			NSApplication.shared.terminate(nil)
		}
	}

	// yt-dlp -U refuses to update the folder build, so updates re-download the release instead
	func updateYtDlp() async {
		var updated = false
		await work("Updating yt-dlp") {
			let version = try await Tools.latestYtDlpVersion()
			self.status = "Downloading yt-dlp \(version)…"
			try await Tools.install(Tools.ytDlpRelease(version))
			updated = true
		}
		if updated {
			await checkYtDlpVersion()
		}
	}

	func checkYtDlpVersion() async {
		var version = ""
		do {
			_ = try await runProcess(Tools.path("yt-dlp"), ["--version"]) { line in
				version = trimmed(line)
			}
		} catch {
			appendLog("!! yt-dlp did not start: \(error.localizedDescription)")
			return
		}
		installed_version = version

		do {
			latest_version = try await Tools.latestYtDlpVersion()
		} catch {
			appendLog("!! Version check failed: \(error.localizedDescription)")
			showIdleStatus("yt-dlp \(version) (could not check for updates)")
			return
		}

		showIdleStatus(
			update_available
				? "yt-dlp \(latest_version ?? "") is available (installed \(version))"
				: "yt-dlp \(version) is up to date"
		)
	}

	// Background checks must not overwrite the status of a running look-up or download
	private func showIdleStatus(_ text: String) {
		if !busy {
			status = text
		}
	}

	func lookUp() async {
		await work("Looking up") {
			var fields: [String: String] = [:]
			let status = try await runProcess(
				Tools.path("yt-dlp"),
				[
					"--skip-download", "--no-playlist", "--no-warnings",
					"--print", "[track] %(track)s",
					"--print", "[artist] %(artist)s",
					"--print", "[artists] %(artists)j",
					"--print", "[video_title] %(title)s",
					"--print", "[uploader] %(uploader,channel)s",
					"--print", "[album] %(album)s",
					"--print", "[year] %(release_year,upload_date>%Y)s",
					"--print", "[chapters] %(chapters)j",
					trimmed(self.url),
				]
			) { line in
				if let match = line.firstMatch(of: /^\[(track|artist|artists|video_title|uploader|album|year|chapters)\] (.*)$/) {
					fields[String(match.1)] = clean(String(match.2))
				} else {
					self.appendLog(line)
				}
			}

			guard status == 0, fields["video_title"]?.isEmpty == false else {
				throw ShellError(message: "Look up failed, see log")
			}

			let guess = lookupGuess(fields)
			self.title = guess.title
			self.artist = guess.artist
			self.artists = guess.artists.joined(separator: "; ")
			self.album = fields["album"] ?? ""
			self.year = fields["year"] ?? ""
			let chapters = decodeChapters(fields["chapters"] ?? "")
			self.chapter_count = chapters.count
			self.parts = chapters.count < 2 ? [] : chapters.map { chapter in
				let part = guessPart(chapterTitle: chapter.title ?? "", artist: guess.artist)
				return Part(start_text: clockTime(chapter.start_time), title: part.title, artist: part.artist, featured: part.featured)
			}
			self.split_parts = false
			self.status = "Found \"\(self.artist) - \(self.title)\""
				+ (chapters.count > 1 ? ", \(chapters.count) chapters" : "")
		}
	}

	func download(to folder: URL, format: AudioFormat, remove_non_music: Bool) async {
		saved_file = nil
		await work("Downloading") {
			let temp_dir = FileManager.default.temporaryDirectory
				.appendingPathComponent("trackget-\(UUID().uuidString)", isDirectory: true)
			defer { try? FileManager.default.removeItem(at: temp_dir) }

			let (source, removed) = try await self.fetchAudio(into: temp_dir, format: format, remove_non_music: remove_non_music)
			self.status = "Tagging…"
			self.progress = nil
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

			if self.split_parts {
				try await self.saveParts(from: source, removed: removed, to: folder)
				return
			}
			let target = uniqueFile(in: folder, name: "\(trimmed(self.artist)) - \(trimmed(self.title))", ext: source.pathExtension)
			try await writeAudio(from: source, to: target, tags: self.trackTags(ext: target.pathExtension), log: self.appendLog)
			self.saved_file = target
			self.status = "Saved \(target.lastPathComponent)"
		}
	}

	private func saveParts(from source: URL, removed: [Chapter], to folder: URL) async throws {
		let starts = parts.compactMap(\.start)
		let included = parts.indices.filter { parts[$0].include }
		var saved = 0
		for (number, index) in included.enumerated() {
			let part = parts[index]
			let start = shiftTime(starts[index], removed: removed)
			let end = index + 1 < starts.count ? shiftTime(starts[index + 1], removed: removed) : nil
			if let end, end - start < 1 {
				appendLog("!! Skipped \"\(part.title)\": SponsorBlock removed all of it")
				continue
			}
			status = "Saving part \(number + 1) of \(included.count)…"
			let target = uniqueFile(in: folder, name: "\(trimmed(part.artist)) - \(trimmed(part.title))", ext: source.pathExtension)
			let tags = partTags(part, number: number + 1, of: included.count, ext: target.pathExtension)
			try await writeAudio(from: source, to: target, tags: tags, range: (start, end), log: appendLog)
			saved_file = target
			saved += 1
		}
		status = "Saved \(saved) of \(included.count) tracks"
	}

	private func trackTags(ext: String) -> [(String, String)] {
		[
			("title", title),
			("artist", artist),
			("ARTISTS", ext == "m4a" ? "" : artists),
			("album", album),
			("album_artist", album_artist),
			("date", year),
			("genre", genre),
			("track", track_number),
		]
	}

	private func partTags(_ part: Part, number: Int, of count: Int, ext: String) -> [(String, String)] {
		[
			("title", part.title),
			("artist", part.artist),
			("ARTISTS", ext == "m4a" ? "" : ([part.artist] + part.featured).joined(separator: "; ")),
			("album", parts_album),
			("album_artist", parts_album_artist),
			("date", year),
			("genre", genre),
			("track", part.track.isEmpty ? "\(number)/\(count)" : part.track),
		]
	}

	private func fetchAudio(into temp_dir: URL, format: AudioFormat, remove_non_music: Bool) async throws -> (URL, [Chapter]) {
		var file_path: String?
		var removed: [Chapter] = []
		var arguments = [
			"--no-playlist", "--newline", "--progress", "--no-simulate",
			"--progress-template", "download:[progress] %(progress._percent_str)s",
			"--print", "after_move:[file] %(filepath)s",
			"--print", "after_move:[removed] %(sponsorblock_chapters)j",
			"-x", "--audio-format", format.rawValue, "--audio-quality", "0",
			"--embed-thumbnail", "--convert-thumbnails", "jpg",
			// Chapters and marked non-music sections become suggestions in the Edit tab
			"--embed-chapters", "--sponsorblock-mark", "music_offtopic",
			"-P", temp_dir.path,
			"-o", "audio.%(ext)s",
		]
		if remove_non_music {
			arguments += ["--sponsorblock-remove", "music_offtopic"]
		}
		arguments.append(trimmed(url))

		let status = try await runProcess(Tools.path("yt-dlp"), arguments) { line in
			if line.hasPrefix("[progress] ") {
				let percent = line.dropFirst(11).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
				if let value = Double(percent) {
					self.progress = value / 100
					self.status = "Downloading… \(Int(value))%"
				}
			} else if line.hasPrefix("[file] ") {
				file_path = String(line.dropFirst(7))
			} else if line.hasPrefix("[removed] ") {
				removed = decodeChapters(String(line.dropFirst(10)))
			} else {
				self.appendLog(line)
			}
		}

		guard status == 0, let file_path else {
			throw ShellError(message: "yt-dlp failed, see log")
		}
		return (URL(fileURLWithPath: file_path), removed)
	}

	private func work(_ label: String, _ body: @MainActor () async throws -> Void) async {
		busy = true
		progress = nil
		status = "\(label)…"
		appendLog("== \(label)")
		do {
			try await body()
		} catch {
			status = error.localizedDescription
			appendLog("!! \(error.localizedDescription)")
		}
		busy = false
	}

	func appendLog(_ line: String) {
		log += line + "\n"
	}
}

private func trimmed(_ value: String) -> String {
	value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func clean(_ value: String) -> String {
	value == "NA" ? "" : trimmed(value)
}

private func lookupGuess(_ fields: [String: String]) -> TrackGuess {
	let track = fields["track"] ?? ""
	var artists = decodeArtists(fields["artists"] ?? "")
	if artists.isEmpty, let artist = fields["artist"], !artist.isEmpty {
		artists = [artist]
	}
	if !track.isEmpty && !artists.isEmpty {
		return trackFromMetadata(track: track, artists: artists)
	}
	return guessTrack(videoTitle: fields["video_title"] ?? "", uploader: fields["uploader"] ?? "")
}

private func decodeArtists(_ json: String) -> [String] {
	guard let list = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else {
		return []
	}
	return list.filter { !$0.isEmpty }
}
