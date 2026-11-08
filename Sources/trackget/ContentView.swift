import AppKit
import SwiftUI

struct ContentView: View {
	@State private var model = Model()
	@State private var show_more = false
	@State private var show_log = false
	@AppStorage("output_folder") private var output_folder = defaultFolder().path
	@AppStorage("audio_format") private var audio_format = AudioFormat.mp3

	var body: some View {
		VStack(spacing: 0) {
			Form {
				Section {
					HStack {
						TextField("URL", text: $model.url, prompt: Text("https://…"))
						Button("Look Up") { Task { await model.lookUp() } }
							.disabled(model.busy || model.url.isEmpty)
					}
				}

				Section {
					TextField("Title", text: $model.title)
					TextField("Artist", text: $model.artist)
					ClickableDisclosure(title: "More details", is_expanded: $show_more) {
						TextField("Album", text: $model.album)
						TextField("All artists", text: $model.artists, prompt: Text("Artist; Featured artist"))
						TextField("Album artist", text: $model.album_artist)
						TextField("Year", text: $model.year)
						TextField("Genre", text: $model.genre)
						TextField("Track number", text: $model.track_number)
					}
				}

				Section {
					HStack {
						LabeledContent("Folder") {
							Text(output_folder)
								.lineLimit(1)
								.truncationMode(.head)
						}
						Button("Choose…", action: chooseFolder)
					}
					Picker("Format", selection: $audio_format) {
						ForEach(AudioFormat.allCases) { format in
							Text(format.rawValue).tag(format)
						}
					}
				}

				Section {
					ClickableDisclosure(title: "Log", is_expanded: $show_log) {
						ScrollView {
							Text(model.log)
								.font(.system(.caption, design: .monospaced))
								.textSelection(.enabled)
								.frame(maxWidth: .infinity, alignment: .leading)
						}
						.frame(height: 160)
					}
				}
			}
			.formStyle(.grouped)
			.disabled(model.busy)

			footer
		}
		.frame(minWidth: 480, minHeight: 520)
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
			await model.checkAppUpdate()
		}
	}

	private var footer: some View {
		HStack(spacing: 12) {
			if model.busy {
				if let progress = model.progress {
					ProgressView(value: progress).frame(width: 120)
				} else {
					ProgressView().controlSize(.small)
				}
			}
			Text(model.status)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
			Spacer()
			if let saved_file = model.saved_file {
				Button("Show in Finder") {
					NSWorkspace.shared.activateFileViewerSelecting([saved_file])
				}
			}
			Button("Download") {
				Task { await model.download(to: URL(fileURLWithPath: output_folder), format: audio_format) }
			}
			.keyboardShortcut(.defaultAction)
			.disabled(!model.can_download)
		}
		.padding()
	}

	private func chooseFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.directoryURL = URL(fileURLWithPath: output_folder)
		if panel.runModal() == .OK, let url = panel.url {
			output_folder = url.path
		}
	}
}

private func defaultFolder() -> URL {
	FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("trackget", isDirectory: true)
}

// The built-in macOS DisclosureGroup only toggles from the chevron
private struct ClickableDisclosure<Content: View>: View {
	let title: String
	@Binding var is_expanded: Bool
	@ViewBuilder let content: () -> Content

	var body: some View {
		DisclosureGroup(isExpanded: $is_expanded, content: content) {
			Text(title)
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
				.onTapGesture {
					withAnimation { is_expanded.toggle() }
				}
		}
	}
}
