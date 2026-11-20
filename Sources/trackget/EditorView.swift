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
			ControlGroup {
				Button("Zoom Out", systemImage: "minus.magnifyingglass") { editor.zoomAroundPlayhead(by: 0.5) }
					.keyboardShortcut("-", modifiers: .command)
					.disabled(!editor.is_zoomed)
				Button("Zoom In", systemImage: "plus.magnifyingglass") { editor.zoomAroundPlayhead(by: 2) }
					.keyboardShortcut("=", modifiers: .command)
					.disabled(editor.view_length <= Editor.shortest_view)
			}
			.fixedSize()
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
	@State private var pinch_scale = 1.0
	@State private var pointer = PointerState()
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
			.simultaneousGesture(
				MagnifyGesture()
					.onChanged { value in
						editor.zoom(by: value.magnification / pinch_scale, around: time(x: value.startLocation.x, width: width))
						pinch_scale = value.magnification
					}
					.onEnded { _ in pinch_scale = 1 }
			)
			.onContinuousHover { phase in
				pointer.width = width
				if case .active(let location) = phase {
					pointer.x = location.x
				} else {
					pointer.x = nil
				}
			}
		}
		.frame(height: 140)
		.focusable()
		.focused($focused)
		.focusEffectDisabled()
		.onKeyPress(.space) {
			editor.togglePlay()
			return .handled
		}
		.onAppear { pointer.start(editor) }
		.onDisappear { pointer.stop() }
		.help("Click to move the playhead and drag the handles. Pinch or ⌘-scroll to zoom, swipe sideways to scroll, space to play.")
	}

	private func time(x: Double, width: Double) -> Double {
		guard width > 0 else {
			return 0
		}
		return editor.view_start + min(max(x / width, 0), 1) * editor.view_length
	}

	private func position(_ time: Double, width: Double) -> Double {
		editor.view_length > 0 ? (time - editor.view_start) / editor.view_length * width : 0
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
		let wave_height = size.height - 8
		let middle = wave_height / 2

		context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(.secondary.opacity(0.08)))

		// Each column shows the loudest peak in its time span, so detail survives at every zoom level
		let peaks = editor.peaks
		if !peaks.isEmpty && editor.duration > 0 {
			let peaks_per_second = Double(peaks.count) / editor.duration
			let column = 2.0
			var inside = Path()
			var outside = Path()
			var x = 0.0
			while x < width {
				let from_time = time(x: x, width: width)
				let first = min(Int(from_time * peaks_per_second), peaks.count - 1)
				let last = min(max(first + 1, Int(time(x: x + column, width: width) * peaks_per_second)), peaks.count)
				let peak = peaks[first..<last].max() ?? 0
				let height = max(1, Double(peak) * (wave_height - 12))
				let bar = CGRect(x: x, y: middle - height / 2, width: column - 0.5, height: height)
				if from_time >= editor.trim_start && from_time <= editor.trim_end {
					inside.addRect(bar)
				} else {
					outside.addRect(bar)
				}
				x += column
			}
			context.fill(outside, with: .color(.secondary.opacity(0.35)))
			context.fill(inside, with: .color(.accentColor))
		}

		for x in [position(editor.trim_start, width: width), position(editor.trim_end, width: width)] {
			context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: wave_height)), with: .color(.primary))
			context.fill(Path(ellipseIn: CGRect(x: x - 5, y: 0, width: 10, height: 10)), with: .color(.primary))
		}
		for cut in editor.cuts {
			let x = position(cut, width: width)
			context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: wave_height)), with: .color(.orange))
			context.fill(Path(ellipseIn: CGRect(x: x - 5, y: wave_height - 10, width: 10, height: 10)), with: .color(.orange))
		}
		let playhead_x = position(editor.playhead, width: width)
		context.fill(Path(CGRect(x: playhead_x - 0.75, y: 0, width: 1.5, height: wave_height)), with: .color(.red))

		if editor.is_zoomed {
			let track = CGRect(x: 0, y: size.height - 3, width: width, height: 3)
			context.fill(Path(roundedRect: track, cornerRadius: 1.5), with: .color(.secondary.opacity(0.2)))
			let visible = CGRect(
				x: editor.view_start / editor.duration * width,
				y: size.height - 3,
				width: max(4, editor.view_length / editor.duration * width),
				height: 3
			)
			context.fill(Path(roundedRect: visible, cornerRadius: 1.5), with: .color(.secondary.opacity(0.7)))
		}
	}
}

// SwiftUI has no scroll wheel events on macOS, so a local event monitor handles them while the pointer is over the waveform
@MainActor
final class PointerState {
	var x: Double?
	var width = 0.0
	private var monitor: Any?

	func start(_ editor: Editor) {
		stop()
		monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
			let delta_x = Double(event.scrollingDeltaX)
			let delta_y = Double(event.scrollingDeltaY)
			let zooming = event.modifierFlags.contains(.command)
			let handled = MainActor.assumeIsolated {
				self?.scroll(editor, delta_x: delta_x, delta_y: delta_y, zooming: zooming) ?? false
			}
			return handled ? nil : event
		}
	}

	private func scroll(_ editor: Editor, delta_x: Double, delta_y: Double, zooming: Bool) -> Bool {
		guard let x, width > 0, editor.view_length > 0 else {
			return false
		}
		let seconds_per_point = editor.view_length / width
		if zooming {
			editor.zoom(by: exp(delta_y * 0.01), around: editor.view_start + x * seconds_per_point)
			return true
		}
		// Vertical scrolling without ⌘ still scrolls the page
		guard abs(delta_x) > abs(delta_y) else {
			return false
		}
		editor.pan(to: editor.view_start - delta_x * seconds_per_point)
		return true
	}

	func stop() {
		if let monitor {
			NSEvent.removeMonitor(monitor)
		}
		monitor = nil
	}
}
