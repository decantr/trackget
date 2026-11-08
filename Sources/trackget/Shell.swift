import Foundation

struct ShellError: LocalizedError {
	let message: String
	var errorDescription: String? { message }
}

@MainActor
func runProcess(
	_ executable: URL,
	_ arguments: [String],
	onLine: (String) -> Void = { _ in }
) async throws -> Int32 {
	let process = Process()
	process.executableURL = executable
	process.arguments = arguments
	process.environment = toolEnvironment()

	let pipe = Pipe()
	process.standardOutput = pipe
	process.standardError = pipe

	try process.run()
	for try await line in pipe.fileHandleForReading.bytes.lines {
		onLine(line)
	}
	while process.isRunning {
		try await Task.sleep(for: .milliseconds(20))
	}
	return process.terminationStatus
}

func toolEnvironment() -> [String: String] {
	var env = ProcessInfo.processInfo.environment
	// Only our own bin dir plus system paths, so brew versions are never picked up
	env["PATH"] = Tools.bin_dir.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
	return env
}
