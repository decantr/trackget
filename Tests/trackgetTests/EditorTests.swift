import Foundation
import Testing
@testable import trackget

@MainActor
struct EditorTests {
	private func editor(duration: Double = 100, title: String = "Foreplay / Long Time") -> Editor {
		let editor = Editor()
		editor.duration = duration
		editor.trim_end = duration
		editor.title = title
		editor.artist = "Boston"
		editor.parts = [EditPart(title: title, artist: "Boston")]
		return editor
	}

	@Test func splitNamesPartsFromTitle() {
		let editor = editor()
		editor.seek(40)
		editor.split()
		#expect(editor.cuts == [40])
		#expect(editor.parts.map(\.title) == ["Foreplay", "Long Time"])
		#expect(editor.boundaries == [0, 40, 100])
	}

	@Test func splitKeepsCutsInOrder() {
		let editor = editor(title: "One")
		editor.seek(60)
		editor.split()
		editor.seek(20)
		editor.split()
		#expect(editor.cuts == [20, 60])
		#expect(editor.parts.count == 3)
	}

	@Test func refusesSplitOnExistingCut() {
		let editor = editor()
		editor.seek(40)
		editor.split()
		editor.seek(40.2)
		#expect(!editor.can_split)
	}

	@Test func markersKeepTheirOrder() {
		let editor = editor()
		editor.seek(40)
		editor.split()
		editor.move(.cut(0), to: 150)
		#expect(editor.cuts == [99.5])
		editor.move(.start, to: 120)
		#expect(editor.trim_start == 99)
		editor.move(.end, to: -5)
		#expect(editor.trim_end == 100)
	}

	@Test func mergeRestoresSingleTrack() {
		let editor = editor()
		editor.seek(40)
		editor.split()
		editor.merge(1)
		#expect(editor.cuts.isEmpty)
		#expect(editor.parts.map(\.title) == ["Foreplay / Long Time"])
	}

	@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: Tools.path("ffmpeg").path)))
	func readsTagsAndPeaks() async throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trackget-test-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let source = folder.appendingPathComponent("source.flac")
		let status = try await runProcess(
			Tools.path("ffmpeg"),
			["-v", "error", "-f", "lavfi", "-i", "sine=d=10", "-metadata", "title=Foreplay", "-metadata", "artist=Boston", source.path]
		)
		#expect(status == 0)

		let info = try await readAudioInfo(source)
		#expect(abs(info.duration - 10) < 0.1)
		#expect(info.tags["title"] == "Foreplay")
		#expect(info.tags["artist"] == "Boston")

		let peaks = try await loadPeaks(source, duration: info.duration, count: 100)
		#expect((100...101).contains(peaks.count))
		#expect(peaks.max() == 1)

		let editor = Editor()
		await editor.open(source)
		editor.seek(4)
		editor.split()
		editor.parts[1].title = "Long Time"
		await editor.save(to: folder)
		let long_time = try await readAudioInfo(folder.appendingPathComponent("Boston - Long Time.flac"))
		#expect(abs(long_time.duration - 6) < 0.1)
		#expect(long_time.tags["track"] == "2/2")
		#expect(long_time.tags["album"] == "Foreplay")
		editor.close()
	}
}

@MainActor
struct EditorZoomTests {
	private func editor() -> Editor {
		let editor = Editor()
		editor.duration = 100
		editor.trim_end = 100
		editor.view_length = 100
		return editor
	}

	@Test func zoomKeepsTimeUnderPointer() {
		let editor = editor()
		editor.zoom(by: 4, around: 50)
		#expect(editor.view_length == 25)
		#expect(editor.view_start == 37.5)
	}

	@Test func zoomStopsAtLimits() {
		let editor = editor()
		editor.zoom(by: 1000, around: 0)
		#expect(editor.view_length == Editor.shortest_view)
		#expect(editor.view_start == 0)
		editor.zoom(by: 0.001, around: 0)
		#expect(editor.view_length == 100)
		#expect(!editor.is_zoomed)
	}

	@Test func panStaysInsideSong() {
		let editor = editor()
		editor.zoom(by: 4, around: 50)
		editor.pan(to: 90)
		#expect(editor.view_start == 75)
		editor.pan(to: -10)
		#expect(editor.view_start == 0)
	}
}

@MainActor
struct EditorSuggestionTests {
	// 0–2 s non-music, Song A from 2 s, silence 10–12 s, Song B from 12 s, non-music 18–20 s
	private func makeFile(in folder: URL) async throws -> URL {
		let metadata = folder.appendingPathComponent("chapters.txt")
		let chapters = [(0, 2000, "[SponsorBlock]: Non-Music Section"), (2000, 12000, "Song A"), (12000, 18000, "Song B"), (18000, 20000, "[SponsorBlock]: Non-Music Section")]
		let text = ";FFMETADATA1\n" + chapters.map { "[CHAPTER]\nTIMEBASE=1/1000\nSTART=\($0.0)\nEND=\($0.1)\ntitle=\($0.2)\n" }.joined()
		try text.write(to: metadata, atomically: true, encoding: .utf8)
		// ffmpeg writes no chapters to flac, so the test uses mp3
		let file = folder.appendingPathComponent("source.mp3")
		let status = try await runProcess(Tools.path("ffmpeg"), [
			"-v", "error",
			"-f", "lavfi", "-i", "sine=d=10",
			"-f", "lavfi", "-t", "2", "-i", "anullsrc=r=44100:cl=mono",
			"-f", "lavfi", "-i", "sine=d=8",
			"-i", metadata.path,
			"-filter_complex", "[0][1][2]concat=n=3:v=0:a=1",
			"-map_chapters", "3",
			file.path,
		])
		#expect(status == 0)
		return file
	}

	@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: Tools.path("ffmpeg").path)))
	func suggestsFromChaptersAndSilence() async throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trackget-test-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }

		let editor = Editor()
		await editor.open(try await makeFile(in: folder))
		editor.artist = "Boston"
		#expect(editor.non_music == [Span(start: 0, end: 2), Span(start: 18, end: 20)])
		#expect(editor.chapters.map(\.title) == ["Song A", "Song B"])
		#expect(editor.silences.count == 1)
		#expect(abs((editor.silence_cuts.first ?? 0) - 11) < 0.2)
		#expect(editor.chapter_cuts == [12])

		editor.splitAtChapters()
		#expect(editor.cuts == [12])
		#expect(editor.parts.map(\.title) == ["Song A", "Song B"])
		#expect(editor.parts.map(\.artist) == ["Boston", "Boston"])

		editor.trimNonMusic()
		#expect(editor.trim_start == 2)
		#expect(editor.trim_end == 18)
		editor.close()
	}
}
