import SwiftUI

enum AppTab: Hashable {
	case download
	case edit
}

struct ContentView: View {
	@State private var model = Model()
	@State private var editor = Editor()
	@State private var tab = AppTab.download

	var body: some View {
		TabView(selection: $tab) {
			DownloadView(model: model) { file in
				tab = .edit
				Task { await editor.open(file) }
			}
			.tabItem { Text("Download") }
			.tag(AppTab.download)

			EditorView(editor: editor)
				.tabItem { Text("Edit") }
				.tag(AppTab.edit)
		}
		.frame(minWidth: 560, minHeight: 560)
		.toolbar {
			Button {
				Task { await model.updateYtDlp() }
			} label: {
				Label(
					model.update_available ? "Update yt-dlp to \(model.latest_version ?? "")" : "Update yt-dlp",
					systemImage: model.update_available ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath"
				)
				.labelStyle(.titleAndIcon)
			}
			.help(model.installed_version.isEmpty ? "Update yt-dlp" : "Installed: yt-dlp \(model.installed_version)")
			.disabled(model.busy)

			if let app_update = model.app_update {
				Button {
					Task { await model.installAppUpdate() }
				} label: {
					Label("Update TrackGet to \(app_update.version)", systemImage: "sparkles")
						.labelStyle(.titleAndIcon)
				}
				.help("Installed: TrackGet \(Updater.current_version). TrackGet restarts after the update.")
				.disabled(model.busy)
			}
		}
		.task {
			await model.prepareTools()
			async let ytdlp_check: Void = model.checkYtDlpVersion()
			async let app_check: Void = model.checkAppUpdate()
			_ = await (ytdlp_check, app_check)
		}
		.onDisappear { editor.close() }
	}
}
