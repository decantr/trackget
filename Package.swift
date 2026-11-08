// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "trackget",
	platforms: [.macOS(.v14)],
	targets: [
		.executableTarget(name: "trackget", path: "Sources/trackget"),
		.testTarget(name: "trackgetTests", dependencies: ["trackget"], path: "Tests/trackgetTests"),
	]
)
