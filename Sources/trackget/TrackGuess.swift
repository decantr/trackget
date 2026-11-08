import Foundation

struct TrackGuess: Equatable {
	var artist: String
	var title: String
	var featured: [String] = []

	var artists: [String] { [artist] + featured }
}

func splitArtists(_ text: String) -> [String] {
	text.split(separator: /\s*(?:,|&|;|\band\b)\s*/)
		.map { collapseSpaces(String($0)) }
		.filter { !$0.isEmpty }
}

// Metadata from YouTube Music lists every artist but keeps featured ones out of the track name
func trackFromMetadata(track: String, artists: [String]) -> TrackGuess {
	var guess = TrackGuess(artist: artists[0], title: track, featured: Array(artists.dropFirst()))
	if !guess.featured.isEmpty && !track.contains(/(?i)\b(feat|ft)\b/) {
		guess.title += " (feat. \(featuredList(guess.featured)))"
	}
	return guess
}

private func featuredList(_ names: [String]) -> String {
	if names.count < 2 {
		return names.joined()
	}
	return names.dropLast().joined(separator: ", ") + " & " + names.last!
}

func guessTrack(videoTitle video_title: String, uploader: String) -> TrackGuess {
	var text = removeNoise(video_title)
	var featuring: String?
	(text, featuring) = extractFeaturing(text)

	var guess: TrackGuess
	if let range = text.firstRange(of: /\s+[-–—]\s+/) {
		var artist = String(text[..<range.lowerBound])
		var artist_featuring: String?
		(artist, artist_featuring) = extractFeaturing(artist)
		featuring = featuring ?? artist_featuring
		guess = TrackGuess(artist: artist, title: String(text[range.upperBound...]))
	} else {
		guess = TrackGuess(artist: cleanChannel(uploader), title: text)
	}

	guess.title = stripQuotes(guess.title)
	if let featuring {
		guess.title += " (feat. \(featuring))"
		guess.featured = splitArtists(featuring)
	}
	guess.artist = collapseSpaces(guess.artist)
	guess.title = collapseSpaces(guess.title)
	return guess
}

private func removeNoise(_ text: String) -> String {
	let noise_words = /(?i)\b(official|video|audio|lyrics?|visuali[sz]er|hd|hq|4k|m\/?v)\b/
	var result = text
	if let bar = result.firstRange(of: /\s+\|\s+/) {
		result = String(result[..<bar.lowerBound])
	}
	result = result.replacing(/\s*[\(\[]([^\)\]]*)[\)\]]/) { match in
		match.1.contains(noise_words) ? "" : String(match.0)
	}
	return result
}

// Returns the text without the featuring clause, plus the featured artists
private func extractFeaturing(_ text: String) -> (String, String?) {
	let in_brackets = /(?i)\s*[\(\[](?:ft\.?|feat\.?|featuring)\s+([^\)\]]+)[\)\]]/
	if let match = text.firstMatch(of: in_brackets) {
		let rest = text.replacingCharacters(in: match.range, with: "")
		return (rest, collapseSpaces(String(match.1)))
	}
	let trailing = /(?i)\s+(?:ft\.?|feat\.?|featuring)\s+(.+?)(?=\s+[-–—]\s+|$)/
	if let match = text.firstMatch(of: trailing) {
		let rest = text.replacingCharacters(in: match.range, with: "")
		return (rest, collapseSpaces(String(match.1)))
	}
	return (text, nil)
}

private func cleanChannel(_ name: String) -> String {
	var result = name
		.replacing(/\s*-\s*Topic$/, with: "")
		.replacing(/VEVO$/, with: "")
		.replacing(/(?i)\s*official$/, with: "")
	if !result.contains(" ") {
		result = result.replacing(/(\p{Ll})(\p{Lu})/) { "\($0.1) \($0.2)" }
	}
	return result
}

private func stripQuotes(_ text: String) -> String {
	text.replacing(/^\s*["“”](.+?)["“”]/) { String($0.1) }
}

private func collapseSpaces(_ text: String) -> String {
	text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
}
