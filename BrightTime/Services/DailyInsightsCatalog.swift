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
    // Only reviewed, source-backed content belongs in this catalog. These starter
    // items make the first version useful before a remotely managed feed exists.
    static func load(bundle: Bundle = .main, now: Date = .now) throws -> [DailyInsight] {
        guard let url = bundle.url(forResource: "daily-insights", withExtension: "json") else {
            return starterItems.filter { $0.isValid(at: now) }
                .sorted { $0.publishedAt > $1.publishedAt }
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

    private static let starterItems: [DailyInsight] = [
        DailyInsight(
            id: "australia-social-media-minimum-age-2026",
            kind: .news,
            title: "Australia's under-16 social media rules are in effect",
            summary: "Age-restricted platforms must take reasonable steps to prevent Australian children under 16 from holding accounts.",
            sourceName: "Australian eSafety Commissioner",
            publishedAt: date("2026-03-31T12:00:00Z"),
            reviewedAt: date("2026-10-11T12:00:00Z"),
            region: "Australia · Under 16",
            sourceURL: URL(string: "https://www.esafety.gov.au/sites/default/files/2026-03/SocialMediaMinimumAgeComplianceUpdateMarch2026.pdf")!
        ),
        DailyInsight(
            id: "aap-digital-ecosystems-2026",
            kind: .guidance,
            title: "AAP says healthy media habits are about more than minutes",
            summary: "Updated guidance encourages families to consider content quality, sleep, movement, relationships, and digital design alongside time limits.",
            sourceName: "American Academy of Pediatrics",
            publishedAt: date("2026-01-20T12:00:00Z"),
            reviewedAt: date("2026-10-11T12:00:00Z"),
            region: "United States · Families",
            sourceURL: URL(string: "https://publications.aap.org/pediatrics/article/doi/10.1542/peds.2025-075320/206129/Digital-Ecosystems-Children-and-Adolescents-Policy")!
        ),
        DailyInsight(
            id: "pew-teens-social-media-2025",
            kind: .statistic,
            title: "45% of U.S. teens say they spend too much time on social media",
            summary: "The same Pew survey found 44% said they had cut back on social media use and 44% had cut back on smartphone use.",
            sourceName: "Pew Research Center",
            publishedAt: date("2025-04-22T12:00:00Z"),
            reviewedAt: date("2026-10-11T12:00:00Z"),
            region: "United States · Ages 13–17",
            sourceURL: URL(string: "https://www.pewresearch.org/internet/2025/04/22/teens-social-media-and-mental-health/")!
        )
    ]

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
