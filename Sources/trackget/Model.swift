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
	var url = ""
	var title = ""
	var artist = ""
	var artists = ""
	var album = ""
	var album_artist = ""
	var year = ""
	var genre = ""
	var track_number = ""

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
		!busy && !trimmed(url).isEmpty && !trimmed(title).isEmpty && !trimmed(artist).isEmpty
	}

	func prepareTools() async {
		await work("Checking tools") {
			for tool in Tools.missing {
				self.status = "Installing \(tool.name)…"
				try await Tools.install(tool)
			}
			try await self.checkVersion()
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

	func updateYtDlp() async {
		await work("Updating yt-dlp") {
			let status = try await runProcess(Tools.path("yt-dlp"), ["-U"], onLine: self.appendLog)
			if status != 0 {
				throw ShellError(message: "yt-dlp update failed, see log")
			}
			try await self.checkVersion()
		}
	}

	private func checkVersion() async throws {
		var version = ""
		_ = try await runProcess(Tools.path("yt-dlp"), ["--version"]) { line in
			version = trimmed(line)
		}
		installed_version = version

		do {
			latest_version = try await Tools.latestYtDlpVersion()
		} catch {
			appendLog("!! Version check failed: \(error.localizedDescription)")
			status = "yt-dlp \(version) (could not check for updates)"
			return
		}

		status = update_available
			? "yt-dlp \(latest_version ?? "") is available (installed \(version))"
			: "yt-dlp \(version) is up to date"
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
					trimmed(self.url),
				]
			) { line in
				if let match = line.firstMatch(of: /^\[(track|artist|artists|video_title|uploader|album|year)\] (.*)$/) {
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
			self.status = "Found \"\(self.artist) - \(self.title)\""
		}
	}

	func download(to folder: URL, format: AudioFormat) async {
		saved_file = nil
		await work("Downloading") {
			let temp_dir = FileManager.default.temporaryDirectory
				.appendingPathComponent("trackget-\(UUID().uuidString)", isDirectory: true)
			defer { try? FileManager.default.removeItem(at: temp_dir) }

			let source = try await self.fetchAudio(into: temp_dir, format: format)
			self.status = "Tagging…"
			self.progress = nil
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			let target = uniqueFile(in: folder, name: "\(trimmed(self.artist)) - \(trimmed(self.title))", ext: source.pathExtension)
			try await self.writeTags(from: source, to: target)

			self.saved_file = target
			self.status = "Saved \(target.lastPathComponent)"
		}
	}

	private func fetchAudio(into temp_dir: URL, format: AudioFormat) async throws -> URL {
		var file_path: String?
		let status = try await runProcess(
			Tools.path("yt-dlp"),
			[
				"--no-playlist", "--newline", "--progress", "--no-simulate",
				"--progress-template", "download:[progress] %(progress._percent_str)s",
				"--print", "after_move:[file] %(filepath)s",
				"-x", "--audio-format", format.rawValue, "--audio-quality", "0",
				"--embed-thumbnail", "--convert-thumbnails", "jpg",
				"-P", temp_dir.path,
				"-o", "audio.%(ext)s",
				trimmed(url),
			]
		) { line in
			if line.hasPrefix("[progress] ") {
				let percent = line.dropFirst(11).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
				if let value = Double(percent) {
					self.progress = value / 100
					self.status = "Downloading… \(Int(value))%"
				}
			} else if line.hasPrefix("[file] ") {
				file_path = String(line.dropFirst(7))
			} else {
				self.appendLog(line)
			}
		}

		guard status == 0, let file_path else {
			throw ShellError(message: "yt-dlp failed, see log")
		}
		return URL(fileURLWithPath: file_path)
	}

	// ffmpeg takes tag values as plain arguments, which avoids yt-dlp's --parse-metadata escaping rules
	private func writeTags(from source: URL, to target: URL) async throws {
		var arguments = ["-nostdin", "-y", "-v", "error", "-i", source.path, "-map", "0", "-c", "copy"]
		let tags: [(String, String)] = [
			("title", title),
			("artist", artist),
			("ARTISTS", target.pathExtension == "m4a" ? "" : artists),
			("album", album),
			("album_artist", album_artist),
			("date", year),
			("genre", genre),
			("track", track_number),
		]
		for (key, value) in tags where !trimmed(value).isEmpty {
			arguments += ["-metadata", "\(key)=\(trimmed(value))"]
		}
		if target.pathExtension == "mp3" {
			arguments += ["-id3v2_version", "3"]
		}
		arguments.append(target.path)

		let status = try await runProcess(Tools.path("ffmpeg"), arguments, onLine: appendLog)
		if status != 0 {
			throw ShellError(message: "ffmpeg tagging failed, see log")
		}
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

private func uniqueFile(in folder: URL, name: String, ext: String) -> URL {
	let safe_name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
	var candidate = folder.appendingPathComponent("\(safe_name).\(ext)")
	var counter = 2
	while FileManager.default.fileExists(atPath: candidate.path) {
		candidate = folder.appendingPathComponent("\(safe_name) (\(counter)).\(ext)")
		counter += 1
	}
	return candidate
}
