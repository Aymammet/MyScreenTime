import Foundation

enum DailyLimitStatus: Equatable {
    case normal
    case nearLimit
    case reached
    case exceeded
}

struct DailyUsageSummary: Equatable {
    let usedMinutes: Int
    let limitMinutes: Int

    var remainingMinutes: Int {
        max(limitMinutes - usedMinutes, 0)
    }

    var overMinutes: Int {
        max(usedMinutes - limitMinutes, 0)
    }

    var progress: Double {
        guard limitMinutes > 0 else { return 0 }
        return min(Double(usedMinutes) / Double(limitMinutes), 1)
    }

    var status: DailyLimitStatus {
        if usedMinutes > limitMinutes { return .exceeded }
        if usedMinutes == limitMinutes { return .reached }
        if usedMinutes * 100 >= limitMinutes * 80 { return .nearLimit }
        return .normal
    }

    var statusText: String {
        if overMinutes > 0 {
            return "\(UsageAggregator.format(minutes: usedMinutes)) used • \(UsageAggregator.format(minutes: overMinutes)) over"
        }

        return "\(UsageAggregator.format(minutes: usedMinutes)) used • \(UsageAggregator.format(minutes: remainingMinutes)) remaining"
    }
}

enum UsageAggregator {
    static func totalMinutes(
        on day: Date,
        childID: UUID,
        sessions: [UsageSession],
        calendar: Calendar = .current
    ) -> Int {
        sessions
            .filter { session in
                session.child?.id == childID
                    && calendar.isDate(session.startedAt, inSameDayAs: day)
            }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    static func totalMinutes(
        on day: Date,
        deviceID: UUID,
        sessions: [UsageSession],
        calendar: Calendar = .current
    ) -> Int {
        sessions
            .filter { session in
                session.device?.id == deviceID
                    && calendar.isDate(session.startedAt, inSameDayAs: day)
            }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    static func summary(
        on day: Date,
        child: ChildProfile,
        sessions: [UsageSession],
        calendar: Calendar = .current
    ) -> DailyUsageSummary {
        DailyUsageSummary(
            usedMinutes: totalMinutes(
                on: day,
                childID: child.id,
                sessions: sessions,
                calendar: calendar
            ),
            limitMinutes: child.limitMinutes(on: day, calendar: calendar)
        )
    }

    static func format(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }
}
