import CryptoKit
import Foundation

struct Tool: Sendable {
	let name: String
	let executable: String
	let url: URL
	let sha256: String?
	let folder: Bool
}

enum Tools {
	static let bin_dir = FileManager.default
		.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("trackget/bin", isDirectory: true)

	static let ffmpeg_release = "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2"

	// The folder build starts in a fraction of a second; the single-file build unpacks itself on every run
	static let ytdlp = Tool(
		name: "yt-dlp",
		executable: "yt-dlp/yt-dlp_macos",
		url: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!,
		sha256: nil,
		folder: true
	)

	static let all: [Tool] = [
		ytdlp,
		Tool(
			name: "ffmpeg",
			executable: "ffmpeg",
			url: URL(string: "\(ffmpeg_release)/ffmpeg.zip")!,
			sha256: "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924",
			folder: false
		),
		Tool(
			name: "ffprobe",
			executable: "ffprobe",
			url: URL(string: "\(ffmpeg_release)/ffprobe.zip")!,
			sha256: "fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6",
			folder: false
		),
		Tool(
			name: "deno",
			executable: "deno",
			url: URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")!,
			sha256: nil,
			folder: false
		),
	]

	static func path(_ name: String) -> URL {
		let tool = all.first { $0.name == name }!
		return bin_dir.appendingPathComponent(tool.executable)
	}

	static var missing: [Tool] {
		all.filter { !FileManager.default.isExecutableFile(atPath: path($0.name).path) }
	}

	static func latestYtDlpVersion() async throws -> String {
		struct Release: Decodable {
			let tag_name: String
		}
		let release: Release = try await fetchJSON("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")
		return release.tag_name
	}

	static func ytDlpRelease(_ version: String) async throws -> Tool {
		let base = "https://github.com/yt-dlp/yt-dlp/releases/download/\(version)"
		let (data, response) = try await URLSession.shared.data(from: URL(string: "\(base)/SHA2-256SUMS")!)
		if let http = response as? HTTPURLResponse, http.statusCode != 200 {
			throw HTTPError(status: http.statusCode, address: "\(base)/SHA2-256SUMS")
		}
		let line = String(decoding: data, as: UTF8.self)
			.split(separator: "\n")
			.first { $0.hasSuffix(" yt-dlp_macos.zip") }
		guard let hash = line?.split(separator: " ").first else {
			throw ShellError(message: "yt-dlp \(version) has no checksum for yt-dlp_macos.zip")
		}
		return Tool(
			name: ytdlp.name,
			executable: ytdlp.executable,
			url: URL(string: "\(base)/yt-dlp_macos.zip")!,
			sha256: String(hash),
			folder: true
		)
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
			if try sha256Hex(of: download) != expected {
				throw ShellError(message: "\(tool.name): checksum mismatch")
			}
		}

		// Unpack beside the target first, so a failed unzip never leaves a half-replaced tool
		let staging = bin_dir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
		defer { try? file_manager.removeItem(at: staging) }
		let status = try await runProcess(
			URL(fileURLWithPath: "/usr/bin/ditto"),
			["-x", "-k", download.path, staging.path]
		)
		if status != 0 {
			throw ShellError(message: "\(tool.name): unzip failed")
		}

		let target = bin_dir.appendingPathComponent(tool.name)
		try? file_manager.removeItem(at: target)
		try file_manager.moveItem(at: tool.folder ? staging : staging.appendingPathComponent(tool.name), to: target)
		try file_manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(tool.name).path)
	}
}

func sha256Hex(of file: URL) throws -> String {
	SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
}

func fetchJSON<T: Decodable>(_ address: String) async throws -> T {
	let (data, response) = try await URLSession.shared.data(from: URL(string: address)!)
	if let http = response as? HTTPURLResponse, http.statusCode != 200 {
		throw HTTPError(status: http.statusCode, address: address)
	}
	return try JSONDecoder().decode(T.self, from: data)
}

struct HTTPError: LocalizedError {
	let status: Int
	let address: String
	var errorDescription: String? { "HTTP \(status) from \(address)" }
}
