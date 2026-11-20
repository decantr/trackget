import AppKit
import SwiftUI

struct DownloadView: View {
	@Bindable var model: Model
	let edit: (URL) -> Void
	@State private var show_more = false
	@State private var show_log = false
	@AppStorage("output_folder") private var output_folder = defaultFolder().path
	@AppStorage("audio_format") private var audio_format = AudioFormat.mp3
	@AppStorage("remove_non_music") private var remove_non_music = true

	var body: some View {
		VStack(spacing: 0) {
			Form {
				Section {
					HStack {
						TextField("URL", text: $model.url, prompt: Text("https://…"))
						Button("Paste", systemImage: "doc.on.clipboard", action: pasteURL)
							.help("Paste URL from clipboard")
							.disabled(model.busy)
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

				if !model.title.isEmpty || !model.parts.isEmpty {
					partsSection
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
					Toggle("Remove non-music parts", isOn: $remove_non_music)
						.help("Cuts intros, skits and outros that SponsorBlock users have marked in music videos")
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
	}

	private var partsSection: some View {
		Section {
			Toggle(
				model.chapter_count > 1 ? "Split into \(model.chapter_count) tracks by chapter" : "Split into tracks",
				isOn: Binding(get: { model.split_parts }, set: { model.setSplit($0) })
			)
			if model.split_parts {
				ForEach($model.parts) { $part in
					HStack {
						Toggle("Include", isOn: $part.include)
							.labelsHidden()
						TextField("Start", text: $part.start_text, prompt: Text("m:ss"))
							.labelsHidden()
							.monospacedDigit()
							.frame(width: 64)
							.foregroundStyle(part.start == nil ? .red : .primary)
						TextField("Title", text: $part.title, prompt: Text("Title"))
							.labelsHidden()
							.disabled(!part.include)
						TextField("Artist", text: $part.artist, prompt: Text("Artist"))
							.labelsHidden()
							.disabled(!part.include)
						Button("Remove part", systemImage: "minus.circle") {
							model.removePart(part.id)
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.borderless)
						.disabled(model.parts.count <= 2)
					}
				}
				Button("Add part", systemImage: "plus.circle") { model.addPart() }
					.buttonStyle(.borderless)
			}
		} footer: {
			if model.split_parts {
				Text(
					model.parts_valid
						? "Album: \(model.parts_album) by \(model.parts_album_artist)"
						: "Start times must be m:ss, in order"
				)
				.foregroundStyle(model.parts_valid ? .secondary : Color.red)
			}
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
				Button("Edit") { edit(saved_file) }
					.help("Trim or split this file in the Edit tab")
			}
			Button("Download") {
				Task { await model.download(to: URL(fileURLWithPath: output_folder), format: audio_format, remove_non_music: remove_non_music) }
			}
			.keyboardShortcut(.defaultAction)
			.disabled(!model.can_download)
		}
		.padding()
	}

	private func pasteURL() {
		guard let text = NSPasteboard.general.string(forType: .string) else {
			return
		}
		model.url = text.trimmingCharacters(in: .whitespacesAndNewlines)
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

func defaultFolder() -> URL {
	FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("trackget", isDirectory: true)
}

// The built-in macOS DisclosureGroup only toggles from the chevron
struct ClickableDisclosure<Content: View>: View {
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
