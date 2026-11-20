import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
	@Bindable var editor: Editor
	@State private var drop_targeted = false
	@AppStorage("output_folder") private var output_folder = defaultFolder().path

	var body: some View {
		VStack(spacing: 0) {
			if editor.file == nil {
				ContentUnavailableView {
					Label("No audio file", systemImage: "waveform")
				} description: {
					Text("Drop an audio file here, or open one.")
				} actions: {
					Button("Open…", action: openFile)
						.disabled(editor.busy)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background {
					RoundedRectangle(cornerRadius: 12)
						.strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
						.padding(16)
				}
			} else {
				Form {
					Section {
						WaveformView(editor: editor)
						controls
					} header: {
						HStack {
							Text(editor.file?.lastPathComponent ?? "")
								.lineLimit(1)
								.truncationMode(.middle)
							Spacer()
							Button("Open…", action: openFile)
								.buttonStyle(.borderless)
						}
					}

					Section {
						TextField("Title", text: $editor.title)
						TextField("Artist", text: $editor.artist)
						TextField("Album", text: $editor.album)
						TextField("Album artist", text: $editor.album_artist)
					}

					if editor.is_split {
						partsSection
					}
				}
				.formStyle(.grouped)
				.disabled(editor.busy)
			}
			footer
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.contentShape(Rectangle())
		.dropDestination(for: URL.self) { urls, _ in
			guard let url = urls.first, isAudio(url) else {
				return false
			}
			Task { await editor.open(url) }
			return true
		} isTargeted: { targeted in
			drop_targeted = targeted
		}
		.overlay {
			if drop_targeted {
				RoundedRectangle(cornerRadius: 12)
					.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
					.background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
					.padding(8)
					.allowsHitTesting(false)
			}
		}
	}

	private var controls: some View {
		HStack {
			Button(editor.playing ? "Pause" : "Play", systemImage: editor.playing ? "pause.fill" : "play.fill") {
				editor.togglePlay()
			}
			.labelStyle(.iconOnly)
			.frame(width: 28)
			Text("\(preciseTime(editor.playhead)) / \(clockTime(editor.duration))")
				.monospacedDigit()
				.foregroundStyle(.secondary)
			Spacer()
			Button("Set Start", action: editor.setStart)
				.help("Cut everything before the playhead")
			Button("Set End", action: editor.setEnd)
				.help("Cut everything after the playhead")
			Button("Split Here", action: editor.split)
				.help("Start a new track at the playhead")
				.disabled(!editor.can_split)
		}
	}

	private var partsSection: some View {
		Section {
			ForEach(editor.parts) { part in
				let index = editor.parts.firstIndex { $0.id == part.id } ?? 0
				let range = editor.boundaries.indices.contains(index + 1) ? "\(clockTime(editor.boundaries[index]))–\(clockTime(editor.boundaries[index + 1]))" : ""
				HStack {
					Toggle("Include", isOn: partBinding(part.id).include)
						.labelsHidden()
					Text(range)
						.monospacedDigit()
						.foregroundStyle(.secondary)
						.frame(width: 96, alignment: .leading)
					TextField("Title", text: partBinding(part.id).title, prompt: Text("Title"))
						.labelsHidden()
						.disabled(!part.include)
					TextField("Artist", text: partBinding(part.id).artist, prompt: Text("Artist"))
						.labelsHidden()
						.disabled(!part.include)
					Button("Join with the part before", systemImage: "minus.circle") {
						if let index = editor.parts.firstIndex(where: { $0.id == part.id }) {
							editor.merge(index)
						}
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.borderless)
					.disabled(index == 0)
				}
			}
		} header: {
			Text("Tracks")
		} footer: {
			Text("Album: \(editor.parts_album) by \(editor.parts_album_artist)")
				.foregroundStyle(.secondary)
		}
	}

	// Rows look parts up by id, because a row can still render once while a new file replaces the parts
	private func partBinding(_ id: EditPart.ID) -> Binding<EditPart> {
		Binding(
			get: { editor.parts.first { $0.id == id } ?? EditPart(title: "", artist: "") },
			set: { part in
				if let index = editor.parts.firstIndex(where: { $0.id == id }) {
					editor.parts[index] = part
				}
			}
		)
	}

	private var footer: some View {
		HStack(spacing: 12) {
			if editor.busy {
				ProgressView().controlSize(.small)
			}
			Text(editor.status)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
			Spacer()
			if let saved_file = editor.saved_file {
				Button("Show in Finder") {
					NSWorkspace.shared.activateFileViewerSelecting([saved_file])
				}
			}
			Button(editor.is_split ? "Save \(editor.parts.filter(\.include).count) Tracks" : "Save") {
				Task { await editor.save(to: URL(fileURLWithPath: output_folder)) }
			}
			.keyboardShortcut(.defaultAction)
			.disabled(!editor.can_save)
		}
		.padding()
	}

	private func openFile() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.audio]
		panel.directoryURL = editor.file?.deletingLastPathComponent() ?? URL(fileURLWithPath: output_folder)
		if panel.runModal() == .OK, let url = panel.url {
			Task { await editor.open(url) }
		}
	}
}

private func isAudio(_ url: URL) -> Bool {
	UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
}

struct WaveformView: View {
	@Bindable var editor: Editor
	@State private var dragging: Marker?
	@FocusState private var focused: Bool

	var body: some View {
		GeometryReader { geometry in
			let width = geometry.size.width
			Canvas { context, size in
				draw(in: &context, size: size)
			}
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { value in
						let marker = dragging ?? nearestMarker(x: value.startLocation.x, width: width)
						dragging = marker
						editor.move(marker, to: time(x: value.location.x, width: width))
						focused = true
					}
					.onEnded { _ in dragging = nil }
			)
		}
		.frame(height: 140)
		.focusable()
		.focused($focused)
		.focusEffectDisabled()
		.onKeyPress(.space) {
			editor.togglePlay()
			return .handled
		}
		.help("Click to move the playhead, drag the handles to trim, space to play")
	}

	private func time(x: Double, width: Double) -> Double {
		guard width > 0 else {
			return 0
		}
		return min(max(x / width, 0), 1) * editor.duration
	}

	private func position(_ time: Double, width: Double) -> Double {
		editor.duration > 0 ? time / editor.duration * width : 0
	}

	// Grabs a marker within a few points of the click, otherwise the click moves the playhead
	private func nearestMarker(x: Double, width: Double) -> Marker {
		let candidates = editor.cuts.indices.map { Marker.cut($0) } + [.start, .end]
		let nearest = candidates.min { abs(position(editor.markerTime($0), width: width) - x) < abs(position(editor.markerTime($1), width: width) - x) }
		if let nearest, abs(position(editor.markerTime(nearest), width: width) - x) < 8 {
			return nearest
		}
		return .playhead
	}

	private func draw(in context: inout GraphicsContext, size: CGSize) {
		let width = size.width
		let middle = size.height / 2
		let start_x = position(editor.trim_start, width: width)
		let end_x = position(editor.trim_end, width: width)

		context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(.secondary.opacity(0.08)))

		let peaks = editor.peaks
		if !peaks.isEmpty {
			let step = width / Double(peaks.count)
			var inside = Path()
			var outside = Path()
			for (index, peak) in peaks.enumerated() {
				let x = Double(index) * step
				let height = max(1, Double(peak) * (size.height - 16))
				let bar = CGRect(x: x, y: middle - height / 2, width: max(1, step - 0.5), height: height)
				if x >= start_x && x <= end_x {
					inside.addRect(bar)
				} else {
					outside.addRect(bar)
				}
			}
			context.fill(outside, with: .color(.secondary.opacity(0.35)))
			context.fill(inside, with: .color(.accentColor))
		}

		for x in [start_x, end_x] {
			context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.primary))
			context.fill(Path(ellipseIn: CGRect(x: x - 5, y: 0, width: 10, height: 10)), with: .color(.primary))
		}
		for cut in editor.cuts {
			let x = position(cut, width: width)
			context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.orange))
			context.fill(Path(ellipseIn: CGRect(x: x - 5, y: size.height - 10, width: 10, height: 10)), with: .color(.orange))
		}
		let playhead_x = position(editor.playhead, width: width)
		context.fill(Path(CGRect(x: playhead_x - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.red))
	}
}
