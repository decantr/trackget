import Testing
@testable import trackget

struct TrackGuessTests {
	@Test(arguments: [
		(
			"Eddie Money - Take Me Home Tonight/Be My Baby (Official Video) ft. Ronnie Spector",
			"EddieMoneyVEVO",
			TrackGuess(artist: "Eddie Money", title: "Take Me Home Tonight/Be My Baby (feat. Ronnie Spector)", featured: ["Ronnie Spector"])
		),
		(
			"Daft Punk - Get Lucky (Official Audio) ft. Pharrell Williams, Nile Rodgers",
			"Daft Punk",
			TrackGuess(artist: "Daft Punk", title: "Get Lucky (feat. Pharrell Williams, Nile Rodgers)", featured: ["Pharrell Williams", "Nile Rodgers"])
		),
		(
			"Calvin Harris ft. Rihanna - This Is What You Came For [Lyrics]",
			"SomeLyricsChannel",
			TrackGuess(artist: "Calvin Harris", title: "This Is What You Came For (feat. Rihanna)", featured: ["Rihanna"])
		),
		(
			"The Beatles – \"Let It Be\" (Remastered 2009)",
			"The Beatles",
			TrackGuess(artist: "The Beatles", title: "Let It Be (Remastered 2009)")
		),
		(
			"Nirvana - Smells Like Teen Spirit (Live at Reading 1992) | HD",
			"NirvanaVEVO",
			TrackGuess(artist: "Nirvana", title: "Smells Like Teen Spirit (Live at Reading 1992)")
		),
		(
			"Bohemian Rhapsody (Official Music Video)",
			"Queen Official",
			TrackGuess(artist: "Queen", title: "Bohemian Rhapsody")
		),
		(
			"Midnight City",
			"M83 - Topic",
			TrackGuess(artist: "M83", title: "Midnight City")
		),
	])
	func guesses(video_title: String, uploader: String, expected: TrackGuess) {
		#expect(guessTrack(videoTitle: video_title, uploader: uploader) == expected)
	}
}

struct TrackFromMetadataTests {
	@Test func addsFeaturedArtistsToTitle() {
		let guess = trackFromMetadata(track: "Get Lucky", artists: ["Daft Punk", "Pharrell Williams", "Nile Rodgers"])
		#expect(guess.title == "Get Lucky (feat. Pharrell Williams & Nile Rodgers)")
		#expect(guess.artist == "Daft Punk")
		#expect(guess.artists == ["Daft Punk", "Pharrell Williams", "Nile Rodgers"])
	}

	@Test func keepsExistingFeaturing() {
		let guess = trackFromMetadata(track: "Stay (feat. Mikky Ekko)", artists: ["Rihanna", "Mikky Ekko"])
		#expect(guess.title == "Stay (feat. Mikky Ekko)")
	}

	@Test func singleArtist() {
		let guess = trackFromMetadata(track: "Midnight City", artists: ["M83"])
		#expect(guess == TrackGuess(artist: "M83", title: "Midnight City"))
	}
}
