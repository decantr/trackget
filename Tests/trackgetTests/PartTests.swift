import Testing
@testable import trackget

struct PartTests {
	@Test func decodesChapters() {
		let json = #"[{"start_time": 0.0, "title": "Intro", "end_time": 12.5}, {"start_time": 12.5, "title": "Be My Baby", "end_time": 200.0}]"#
		#expect(decodeChapters(json) == [
			Chapter(start_time: 0, end_time: 12.5, title: "Intro"),
			Chapter(start_time: 12.5, end_time: 200, title: "Be My Baby"),
		])
		#expect(decodeChapters("").isEmpty)
	}

	@Test func matchesShiftedChapters() {
		let looked_up = [
			Chapter(start_time: 0, end_time: 10, title: "Intro"),
			Chapter(start_time: 10, end_time: 100, title: "Song A"),
			Chapter(start_time: 100, end_time: 200, title: "Song B"),
		]
		let downloaded = [
			Chapter(start_time: 0, end_time: 90, title: "Song A"),
			Chapter(start_time: 90, end_time: 190, title: "Song B"),
		]
		#expect(matchChapters(looked_up, in: downloaded) == [nil, downloaded[0], downloaded[1]])
	}

	@Test func matchesRepeatedTitlesInOrder() {
		let chapters = [
			Chapter(start_time: 0, end_time: 10, title: "Interlude"),
			Chapter(start_time: 10, end_time: 20, title: "Interlude"),
		]
		#expect(matchChapters(chapters, in: chapters) == chapters)
	}

	@Test(arguments: [(5.0, "0:05"), (65.4, "1:05"), (3725.0, "1:02:05")])
	func formatsClockTime(seconds: Double, expected: String) {
		#expect(clockTime(seconds) == expected)
	}

	@Test func guessesPartFromNumberedChapter() {
		#expect(guessPart(chapterTitle: "2. Be My Baby", artist: "Eddie Money") == TrackGuess(artist: "Eddie Money", title: "Be My Baby"))
		#expect(guessPart(chapterTitle: "Ronnie Spector - Be My Baby", artist: "Eddie Money") == TrackGuess(artist: "Ronnie Spector", title: "Be My Baby"))
	}
}
