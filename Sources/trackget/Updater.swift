import Foundation

struct AppRelease: Sendable {
	let version: String
	let zip_url: URL
	let checksum_url: URL
}

enum Updater {
	static let repo = "decantr/trackget"
	static let zip_name = "TrackGet.zip"

	static var current_version: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
	}

	static func latestRelease() async throws -> AppRelease? {
		struct Asset: Decodable {
			let name: String
			let browser_download_url: URL
		}
		struct Release: Decodable {
			let tag_name: String
			let assets: [Asset]
		}
		struct CommitResponse: Decodable {
			struct Commit: Decodable {
				struct Verification: Decodable {
					let verified: Bool
				}
				let verification: Verification
			}
			let commit: Commit
		}

		let release: Release
		do {
			release = try await fetchJSON("https://api.github.com/repos/\(repo)/releases/latest")
		} catch let error as HTTPError where error.status == 404 {
			return nil
		}

		let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
		guard current_version.compare(version, options: .numeric) == .orderedAscending else {
			return nil
		}

		let commit: CommitResponse = try await fetchJSON("https://api.github.com/repos/\(repo)/commits/\(release.tag_name)")
		guard commit.commit.verification.verified else {
			throw ShellError(message: "TrackGet \(version) is not from a verified commit, update skipped")
		}

		guard
			let zip = release.assets.first(where: { $0.name == zip_name }),
			let checksum = release.assets.first(where: { $0.name == zip_name + ".sha256" })
		else {
			throw ShellError(message: "TrackGet \(version) has no \(zip_name) asset")
		}
		return AppRelease(version: version, zip_url: zip.browser_download_url, checksum_url: checksum.browser_download_url)
	}

	// Stages the new app and starts a helper that swaps it in once this process exits
	@MainActor
	static func stage(_ release: AppRelease, log: (String) -> Void) async throws {
		let bundle = Bundle.main.bundleURL
		guard bundle.pathExtension == "app" else {
			throw ShellError(message: "Not running from an .app bundle")
		}

		let work_dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("trackget-update-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: work_dir, withIntermediateDirectories: true)

		let (zip, _) = try await URLSession.shared.download(from: release.zip_url)
		defer { try? FileManager.default.removeItem(at: zip) }
		let (checksum_data, _) = try await URLSession.shared.data(from: release.checksum_url)
		let expected = String(decoding: checksum_data, as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
		guard try sha256Hex(of: zip) == expected else {
			throw ShellError(message: "Update checksum mismatch")
		}

		let tools = URL(fileURLWithPath: "/usr/bin")
		if try await runProcess(tools.appendingPathComponent("ditto"), ["-x", "-k", zip.path, work_dir.path], onLine: log) != 0 {
			throw ShellError(message: "Could not unzip update")
		}
		let new_app = work_dir.appendingPathComponent("TrackGet.app")
		if try await runProcess(tools.appendingPathComponent("codesign"), ["--verify", "--deep", "--strict", new_app.path], onLine: log) != 0 {
			throw ShellError(message: "Update failed code signature check")
		}

		let script = work_dir.appendingPathComponent("swap.sh")
		try swap_script.write(to: script, atomically: true, encoding: .utf8)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), new_app.path, bundle.path]
		try process.run()
	}

	private static let swap_script = """
		pid="$1"
		new_app="$2"
		target="$3"
		while kill -0 "$pid" 2>/dev/null; do
			sleep 0.2
		done
		rm -rf "$target.old"
		if mv "$target" "$target.old" && mv "$new_app" "$target"; then
			rm -rf "$target.old"
		else
			mv "$target.old" "$target"
		fi
		open "$target"
		"""
}
