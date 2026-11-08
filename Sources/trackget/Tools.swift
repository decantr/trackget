import CryptoKit
import Foundation

struct Tool: Sendable {
	let name: String
	let url: URL
	let sha256: String?
	let zipped: Bool
}

enum Tools {
	static let bin_dir = FileManager.default
		.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("trackget/bin", isDirectory: true)

	static let ffmpeg_release = "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2"

	// yt-dlp and deno track latest and update themselves; ffmpeg is pinned
	static let all: [Tool] = [
		Tool(
			name: "yt-dlp",
			url: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!,
			sha256: nil,
			zipped: false
		),
		Tool(
			name: "ffmpeg",
			url: URL(string: "\(ffmpeg_release)/ffmpeg.zip")!,
			sha256: "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924",
			zipped: true
		),
		Tool(
			name: "ffprobe",
			url: URL(string: "\(ffmpeg_release)/ffprobe.zip")!,
			sha256: "fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6",
			zipped: true
		),
		Tool(
			name: "deno",
			url: URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")!,
			sha256: nil,
			zipped: true
		),
	]

	static func path(_ name: String) -> URL {
		bin_dir.appendingPathComponent(name)
	}

	static var missing: [Tool] {
		all.filter { !FileManager.default.isExecutableFile(atPath: path($0.name).path) }
	}

	static func latestYtDlpVersion() async throws -> String {
		struct Release: Decodable {
			let tag_name: String
		}
		let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try JSONDecoder().decode(Release.self, from: data).tag_name
	}

	static func install(_ tool: Tool) async throws {
		let file_manager = FileManager.default
		try file_manager.createDirectory(at: bin_dir, withIntermediateDirectories: true)

		let (download, response) = try await URLSession.shared.download(from: tool.url)
		defer { try? file_manager.removeItem(at: download) }

		if let http = response as? HTTPURLResponse, http.statusCode != 200 {
			throw ShellError(message: "\(tool.name): download failed with HTTP \(http.statusCode)")
		}

		if let expected = tool.sha256 {
			let digest = SHA256.hash(data: try Data(contentsOf: download))
			let actual = digest.map { String(format: "%02x", $0) }.joined()
			if actual != expected {
				throw ShellError(message: "\(tool.name): checksum mismatch")
			}
		}

		let target = path(tool.name)
		try? file_manager.removeItem(at: target)

		if tool.zipped {
			let status = try await runProcess(
				URL(fileURLWithPath: "/usr/bin/ditto"),
				["-x", "-k", download.path, bin_dir.path]
			)
			if status != 0 {
				throw ShellError(message: "\(tool.name): unzip failed")
			}
		} else {
			try file_manager.moveItem(at: download, to: target)
		}

		try file_manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
	}
}
