import Foundation

// ffmpeg takes tag values as plain arguments, which avoids yt-dlp's --parse-metadata escaping rules; an empty value removes the tag
@MainActor
func writeAudio(
	from source: URL,
	to target: URL,
	tags: [(String, String)],
	range: (Double, Double?)? = nil,
	log: (String) -> Void
) async throws {
	var arguments = ["-nostdin", "-y", "-v", "error"]
	// Seeking on the input keeps the cover art stream, which starts at zero
	if let (start, end) = range {
		arguments += ["-ss", String(format: "%.3f", start)]
		if let end {
			arguments += ["-to", String(format: "%.3f", end)]
		}
	}
	// Only audio and cover art: m4a keeps chapters in a data stream that ffmpeg cannot copy back
	arguments += ["-i", source.path, "-map", "0:a", "-map", "0:v?", "-c", "copy"]
	if range != nil {
		arguments += ["-map_chapters", "-1"]
	}
	// A copied flac stream keeps the full-length header; flac to flac is lossless
	if range != nil && target.pathExtension == "flac" {
		arguments += ["-c:a", "flac"]
	}
	for (key, value) in tags {
		arguments += ["-metadata", "\(key)=\(value.trimmingCharacters(in: .whitespacesAndNewlines))"]
	}
	if target.pathExtension == "mp3" {
		arguments += ["-id3v2_version", "3"]
	}
	arguments.append(target.path)

	var last_line = ""
	let status = try await runProcess(Tools.path("ffmpeg"), arguments) { line in
		last_line = line
		log(line)
	}
	if status != 0 {
		try? FileManager.default.removeItem(at: target)
		throw ShellError(message: "ffmpeg failed: \(last_line)")
	}
}

struct AudioInfo {
	let duration: Double
	let chapters: [Chapter]
	// Keys are lowercase, because flac and opus store tags in upper case
	let tags: [String: String]
}

@MainActor
func readAudioInfo(_ file: URL) async throws -> AudioInfo {
	struct Probe: Decodable {
		struct Format: Decodable {
			let duration: String?
			let tags: [String: String]?
		}
		struct Stream: Decodable {
			let tags: [String: String]?
		}
		struct ProbeChapter: Decodable {
			let start_time: String
			let end_time: String
			let tags: [String: String]?
		}
		let format: Format
		let streams: [Stream]?
		let chapters: [ProbeChapter]?
	}
	var output = ""
	let status = try await runProcess(
		Tools.path("ffprobe"),
		["-v", "error", "-select_streams", "a:0", "-show_chapters", "-show_entries", "format=duration:format_tags:stream_tags", "-of", "json", file.path]
	) { line in
		output += line + "\n"
	}
	guard status == 0, let probe = try? JSONDecoder().decode(Probe.self, from: Data(output.utf8)) else {
		throw ShellError(message: "Could not read \(file.lastPathComponent)")
	}
	// Ogg files keep their tags on the stream, other formats on the container
	var tags: [String: String] = [:]
	for (key, value) in (probe.streams?.first?.tags ?? [:]).merging(probe.format.tags ?? [:], uniquingKeysWith: { $1 }) {
		tags[key.lowercased()] = value
	}
	let chapters = (probe.chapters ?? []).map { chapter in
		Chapter(start_time: Double(chapter.start_time) ?? 0, end_time: Double(chapter.end_time) ?? 0, title: chapter.tags?["title"])
	}
	return AudioInfo(duration: Double(probe.format.duration ?? "") ?? 0, chapters: chapters, tags: tags)
}

// Streams decoded samples through a small buffer, so a long file never sits in memory
func loadPeaks(_ file: URL, duration: Double, count: Int) async throws -> [Float] {
	let sample_rate = 8000.0
	let ffmpeg = Tools.path("ffmpeg")
	let environment = toolEnvironment()
	return try await Task.detached {
		let process = Process()
		process.executableURL = ffmpeg
		process.arguments = ["-nostdin", "-v", "error", "-i", file.path, "-map", "0:a:0", "-ac", "1", "-ar", "8000", "-f", "f32le", "pipe:1"]
		process.environment = environment
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		try process.run()

		let per_peak = max(1, Int(duration * sample_rate) / count)
		var peaks: [Float] = []
		peaks.reserveCapacity(count + 1)
		var current: Float = 0
		var in_peak = 0
		var leftover = Data()
		while let chunk = try pipe.fileHandleForReading.read(upToCount: 1 << 16), !chunk.isEmpty {
			let data = leftover + chunk
			let usable = data.count / 4 * 4
			data.withUnsafeBytes { raw in
				for offset in stride(from: 0, to: usable, by: 4) {
					current = max(current, abs(raw.loadUnaligned(fromByteOffset: offset, as: Float.self)))
					in_peak += 1
					if in_peak == per_peak {
						peaks.append(current)
						current = 0
						in_peak = 0
					}
				}
			}
			leftover = Data(data.dropFirst(usable))
		}
		process.waitUntilExit()
		if in_peak > 0 {
			peaks.append(current)
		}
		let loudest = peaks.max() ?? 0
		return loudest > 0 ? peaks.map { $0 / loudest } : peaks
	}.value
}

struct Span: Equatable {
	let start: Double
	let end: Double

	var middle: Double { (start + end) / 2 }
}

// A gap between songs is usually at least a second below -40 dB
@MainActor
func detectSilence(_ file: URL, noise: String = "-40dB", seconds: Double = 1) async throws -> [Span] {
	var spans: [Span] = []
	var start: Double?
	let status = try await runProcess(
		Tools.path("ffmpeg"),
		["-nostdin", "-nostats", "-i", file.path, "-map", "0:a:0", "-af", "silencedetect=noise=\(noise):d=\(seconds)", "-f", "null", "-"]
	) { line in
		if let match = line.firstMatch(of: /silence_start: (-?[\d.]+)/) {
			start = max(0, Double(match.1) ?? 0)
		} else if let match = line.firstMatch(of: /silence_end: ([\d.]+)/), let from = start, let end = Double(match.1) {
			spans.append(Span(start: from, end: end))
			start = nil
		}
	}
	if status != 0 {
		throw ShellError(message: "Silence detection failed")
	}
	return spans
}

func uniqueFile(in folder: URL, name: String, ext: String) -> URL {
	let safe_name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
	var candidate = folder.appendingPathComponent("\(safe_name).\(ext)")
	var counter = 2
	while FileManager.default.fileExists(atPath: candidate.path) {
		candidate = folder.appendingPathComponent("\(safe_name) (\(counter)).\(ext)")
		counter += 1
	}
	return candidate
}
