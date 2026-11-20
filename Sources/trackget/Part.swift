import Foundation

struct Chapter: Decodable, Equatable {
	let start_time: Double
	let end_time: Double
	let title: String?
}

struct Part: Identifiable {
	let id = UUID()
	let chapter: Chapter
	var include = true
	var title: String
	var artist: String
	var featured: [String]

	var time_range: String { "\(clockTime(chapter.start_time))–\(clockTime(chapter.end_time))" }
}

func decodeChapters(_ json: String) -> [Chapter] {
	(try? JSONDecoder().decode([Chapter].self, from: Data(json.utf8))) ?? []
}

// SponsorBlock removal shifts chapter times, so look-up chapters are matched by title to the downloaded ones
func matchChapters(_ parts: [Chapter], in downloaded: [Chapter]) -> [Chapter?] {
	var remaining = downloaded[...]
	return parts.map { part in
		guard let index = remaining.firstIndex(where: { $0.title == part.title }) else {
			return nil
		}
		remaining = remaining[(index + 1)...]
		return downloaded[index]
	}
}

func clockTime(_ seconds: Double) -> String {
	let total = Int(seconds.rounded())
	if total >= 3600 {
		return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
	}
	return String(format: "%d:%02d", total / 60, total % 60)
}
