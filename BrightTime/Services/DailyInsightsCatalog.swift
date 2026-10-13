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
            summary: "Age-restricted platforms must take reasonable steps to prevent Australian kids under 16 from holding accounts.",
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
        ),
        DailyInsight(
            id: "jama-addictive-use-2025",
            kind: .statistic,
            title: "How kids use screens matters more than how long",
            summary: "A 4-year study of 4,285 U.S. youths linked hard-to-control phone or social media use to about twice the risk of suicidal behaviour, and gaming to about 1.5 times. Total screen time was not linked.",
            sourceName: "JAMA",
            publishedAt: date("2025-06-18T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "United States · Ages 9–14",
            sourceURL: URL(string: "https://jamanetwork.com/journals/jama/fullarticle/2835481")!
        ),
        DailyInsight(
            id: "jama-myopia-screen-time-2025",
            kind: .statistic,
            title: "Each extra hour of screens a day raises myopia odds by 21%",
            summary: "A review of 45 studies with 335,524 young people found little added risk under one hour a day. At four hours, the odds of nearsightedness nearly doubled.",
            sourceName: "JAMA Network Open",
            publishedAt: date("2025-02-21T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "Global · Children & young adults",
            sourceURL: URL(string: "https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2830598")!
        ),
        DailyInsight(
            id: "common-sense-census-2025",
            kind: .statistic,
            title: "Young kids' gaming time is up 65% since 2020",
            summary: "Kids 8 and under average about 2.5 hours of screens a day. 40% have their own tablet by age 2, and short videos on TikTok and YouTube Shorts are on the rise.",
            sourceName: "Common Sense Media",
            publishedAt: date("2025-02-26T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "United States · Ages 0–8",
            sourceURL: URL(string: "https://www.commonsensemedia.org/press-releases/digital-childhood-starts-at-age-two-landmark-study-shows-evolution-of-young-childrens-media-use")!
        ),
        DailyInsight(
            id: "pew-teens-youtube-2024",
            kind: .statistic,
            title: "73% of teens watch YouTube every day",
            summary: "15% say they're on it almost constantly. Nearly half of teens (46%) say they're online almost constantly, up from 24% a decade earlier.",
            sourceName: "Pew Research Center",
            publishedAt: date("2024-12-12T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "United States · Ages 13–17",
            sourceURL: URL(string: "https://www.pewresearch.org/internet/2024/12/12/teens-social-media-and-technology-2024/")!
        ),
        DailyInsight(
            id: "otago-screens-in-bed-2024",
            kind: .statistic,
            title: "Screens in bed cost kids sleep, gaming most of all",
            summary: "Teens who used screens once in bed fell asleep about 30 minutes later. Each extra 10 minutes of gaming or multitasking in bed cut about 10 minutes of sleep. Screens before bed mattered less.",
            sourceName: "University of Otago · JAMA Pediatrics",
            publishedAt: date("2024-09-04T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "New Zealand · Ages 11–14",
            sourceURL: URL(string: "https://www.otago.ac.nz/news/newsroom/keep-devices-out-of-bed-for-better-sleep-study")!
        ),
        DailyInsight(
            id: "who-gaming-disorder",
            kind: .guidance,
            title: "When gaming becomes a disorder",
            summary: "WHO looks for three signs lasting about 12 months: losing control over gaming, putting it ahead of other activities, and carrying on despite harm. Only a small share of gamers are affected.",
            sourceName: "World Health Organization",
            publishedAt: date("2020-10-22T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "Global · Gamers",
            sourceURL: URL(string: "https://www.who.int/news-room/q-a-detail/gaming-disorder")!
        ),
        DailyInsight(
            id: "who-under-five-2019",
            kind: .guidance,
            title: "No screens for babies, at most an hour a day for ages 2 to 4",
            summary: "WHO advises no screen time before age 1 and no more than 1 hour a day for ages 2 to 4, with less being better. When kids sit still, reading and storytelling with a caregiver are encouraged.",
            sourceName: "World Health Organization",
            publishedAt: date("2019-04-24T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "Global · Under 5",
            sourceURL: URL(string: "https://www.who.int/news/item/24-04-2019-to-grow-up-healthy-children-need-to-sit-less-and-play-more")!
        ),
        DailyInsight(
            id: "canada-24-hour-guidelines",
            kind: .guidance,
            title: "Canada: no more than 2 hours of fun screen time a day",
            summary: "Canada's 24-hour movement guidelines for ages 5 to 17 pair that limit with at least 60 minutes of active play and 9 to 11 hours of sleep for ages 5 to 13.",
            sourceName: "Canadian Society for Exercise Physiology",
            publishedAt: date("2016-06-15T12:00:00Z"),
            reviewedAt: date("2026-10-12T12:00:00Z"),
            region: "Canada · Ages 5–17",
            sourceURL: URL(string: "https://csepguidelines.ca/guidelines/children-youth/")!
        )
    ]

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
