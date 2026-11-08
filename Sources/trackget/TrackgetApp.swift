import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}
}

@main
struct TrackgetApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var app_delegate

	var body: some Scene {
		Window("trackget", id: "main") {
			ContentView()
		}
		.windowResizability(.contentMinSize)
	}
}
