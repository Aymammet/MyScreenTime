import Foundation

struct DailyInsight: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case statistic, news, guidance
    }

    let id: String
    let kind: Kind
    let title: String
    let summary: String
    let sourceName: String
    let publishedAt: Date
    let reviewedAt: Date
    let region: String
    let sourceURL: URL

    func isValid(at now: Date) -> Bool {
        [id, title, summary, sourceName, region].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && sourceURL.scheme == "https" && sourceURL.host != nil
            && publishedAt <= now && reviewedAt <= now && reviewedAt >= publishedAt
    }

    func needsReview(at now: Date) -> Bool {
        now.timeIntervalSince(reviewedAt) > 30 * 24 * 60 * 60
    }
}

enum DailyInsightsCatalog {
    // Only reviewed, source-backed content belongs in this catalog. No sample claims ship.
    static func load(bundle: Bundle = .main, now: Date = .now) throws -> [DailyInsight] {
        guard let url = bundle.url(forResource: "daily-insights", withExtension: "json") else {
            return []
        }
        return try decode(Data(contentsOf: url), now: now)
    }

    static func decode(_ data: Data, now: Date) throws -> [DailyInsight] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([DailyInsight].self, from: data)
        return items.filter { $0.isValid(at: now) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }
}
