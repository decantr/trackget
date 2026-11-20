import Foundation

struct Chapter: Decodable, Equatable {
	let start_time: Double
	let end_time: Double
	let title: String?
}

struct Part: Identifiable {
	let id = UUID()
	var include = true
	var start_text: String
	var title: String
	var artist: String
	var featured: [String] = []

	var start: Double? { parseClock(start_text) }
}

func decodeChapters(_ json: String) -> [Chapter] {
	(try? JSONDecoder().decode([Chapter].self, from: Data(json.utf8))) ?? []
}

// Part times come from the original video; SponsorBlock removal moves everything after a cut earlier
func shiftTime(_ time: Double, removed: [Chapter]) -> Double {
	var cut = 0.0
	var covered_to = 0.0
	for segment in removed.sorted(by: { $0.start_time < $1.start_time }) {
		let start = max(segment.start_time, covered_to)
		let end = min(segment.end_time, time)
		if end > start {
			cut += end - start
		}
		covered_to = max(covered_to, segment.end_time)
	}
	return time - cut
}

func parseClock(_ text: String) -> Double? {
	let fields = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
	guard (1...3).contains(fields.count) else {
		return nil
	}
	var seconds = 0.0
	for field in fields {
		guard let value = Double(field), value >= 0 else {
			return nil
		}
		seconds = seconds * 60 + value
	}
	return seconds
}

func clockTime(_ seconds: Double) -> String {
	let total = Int(seconds.rounded())
	if total >= 3600 {
		return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
	}
	return String(format: "%d:%02d", total / 60, total % 60)
}
