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

	@Test(arguments: [(2.0, 0.0), (10.0, 6.0), (100.0, 96.0), (150.0, 116.0), (300.0, 256.0)])
	func shiftsTimeAfterRemovedSegments(time: Double, expected: Double) {
		let removed = [
			Chapter(start_time: 0, end_time: 4, title: nil),
			Chapter(start_time: 120, end_time: 160, title: nil),
			Chapter(start_time: 130, end_time: 140, title: nil),
		]
		#expect(shiftTime(time, removed: removed) == expected)
	}

	@Test(arguments: [("0:00", 0.0), ("2:28", 148.0), ("1:02:05", 3725.0), ("95", 95.0), ("2:28.5", 148.5)])
	func parsesClock(text: String, expected: Double) {
		#expect(parseClock(text) == expected)
	}

	@Test(arguments: ["", "2:", "a:10", "1:2:3:4", "-5"])
	func rejectsBadClock(text: String) {
		#expect(parseClock(text) == nil)
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

struct SplitTitleTests {
	@Test(arguments: [
		("Foreplay / Long Time", ["Foreplay", "Long Time"]),
		("Take Me Home Tonight/Be My Baby (feat. Ronnie Spector)", ["Take Me Home Tonight", "Be My Baby (feat. Ronnie Spector)"]),
		("24/7", ["24/7"]),
		("Midnight City", ["Midnight City"]),
	])
	func splitsTitle(title: String, expected: [String]) {
		#expect(splitTitle(title) == expected)
	}
}
