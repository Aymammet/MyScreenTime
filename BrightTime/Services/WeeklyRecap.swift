import Foundation

/// The family's week in numbers, for the Monday report screen and its share card.
struct WeeklyRecap: Equatable {
    struct Kid: Identifiable, Equatable {
        let id: UUID
        let name: String
        let colorHex: UInt32
        let totalMinutes: Int
        let previousMinutes: Int
        /// Days at or under the limit, out of `daysCounted`.
        let daysOnTrack: Int
        let daysCounted: Int
        /// On-track days in a row, ending with the last day counted.
        let streak: Int
        /// Minutes earned into the time bank this week (not counting extra time a
        /// parent approved).
        let earnedMinutes: Int
        /// The day with the most time left under the limit.
        let bestDay: Date?

        var averageMinutes: Int {
            daysCounted > 0 ? totalMinutes / daysCounted : 0
        }
    }

    let interval: DateInterval
    let totalMinutes: Int
    let previousMinutes: Int
    let kids: [Kid]
    /// The family's lightest day of screen time (days with something logged).
    let bestDay: Date?
    let bestDayMinutes: Int

    var change: Int { totalMinutes - previousMinutes }

    var changePercent: Int? {
        guard previousMinutes > 0 else { return nil }
        return Int((Double(change) / Double(previousMinutes) * 100).rounded())
    }

    var title: String {
        let lastDay = interval.end.addingTimeInterval(-1)
        let start = interval.start.formatted(.dateTime.month(.abbreviated).day())
        let end = lastDay.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    var hasUsage: Bool { totalMinutes > 0 }
}

@MainActor
enum WeeklyRecapCalculator {
    /// Weekly reports always cover the last completed Monday–Sunday period. This
    /// stays independent of the chart preference for which day starts a week,
    /// because the report is delivered at the beginning of Monday.
    static func recapInterval(now: Date = .now, calendar: Calendar = AppCalendar.day) -> DateInterval {
        var reportCalendar = calendar
        reportCalendar.firstWeekday = 2
        reportCalendar.minimumDaysInFirstWeek = 1
        guard let current = reportCalendar.dateInterval(of: .weekOfYear, for: now) else {
            let end = reportCalendar.startOfDay(for: now)
            let start = reportCalendar.date(byAdding: .day, value: -7, to: end) ?? end
            return DateInterval(start: start, end: end)
        }
        let start = reportCalendar.date(byAdding: .weekOfYear, value: -1, to: current.start) ?? current.start
        return DateInterval(start: start, end: current.start)
    }

    static func make(
        children: [ChildProfile],
        sessions: [UsageSession],
        now: Date = .now,
        calendar: Calendar = AppCalendar.day,
        interval requestedInterval: DateInterval? = nil
    ) -> WeeklyRecap {
        let interval = requestedInterval ?? recapInterval(now: now, calendar: calendar)
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start) ?? interval.start
        let previous = DateInterval(start: previousStart, end: interval.start)
        let active = children.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
        let ids = Set(active.map(\.id))

        // The days to count: the whole week, but never days still ahead.
        let lastCounted = min(now, interval.end.addingTimeInterval(-1))
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day <= lastCounted && day < interval.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }

        let kids = active.map { child in
            var onTrack = 0
            var streak = 0
            var best: (day: Date, spare: Int)?
            for day in days {
                let used = UsageAggregator.totalMinutes(on: day, childID: child.id, sessions: sessions, calendar: calendar)
                let limit = child.limitMinutes(on: day, calendar: calendar)
                if used <= limit {
                    onTrack += 1
                    streak += 1
                    if used > 0, best.map({ limit - used > $0.spare }) ?? true {
                        best = (day, limit - used)
                    }
                } else {
                    streak = 0
                }
            }
            let earned = child.timeCredits
                .filter { $0.kind == .earned && $0.title != KidRequests.extraTimeTitle && interval.contains($0.day) }
                .reduce(0) { $0 + $1.minutes }
            return WeeklyRecap.Kid(
                id: child.id,
                name: child.name,
                colorHex: child.color.hex,
                totalMinutes: UsageAggregator.totalMinutes(in: interval, childIDs: [child.id], sessions: sessions),
                previousMinutes: UsageAggregator.totalMinutes(in: previous, childIDs: [child.id], sessions: sessions),
                daysOnTrack: onTrack,
                daysCounted: days.count,
                streak: streak,
                earnedMinutes: earned,
                bestDay: best?.day
            )
        }

        var familyBest: (day: Date, minutes: Int)?
        for day in days {
            let minutes = active.reduce(0) {
                $0 + UsageAggregator.totalMinutes(on: day, childID: $1.id, sessions: sessions, calendar: calendar)
            }
            if minutes > 0, familyBest.map({ minutes < $0.minutes }) ?? true {
                familyBest = (day, minutes)
            }
        }

        return WeeklyRecap(
            interval: interval,
            totalMinutes: UsageAggregator.totalMinutes(in: interval, childIDs: ids, sessions: sessions),
            previousMinutes: UsageAggregator.totalMinutes(in: previous, childIDs: ids, sessions: sessions),
            kids: kids,
            bestDay: familyBest?.day,
            bestDayMinutes: familyBest?.minutes ?? 0
        )
    }
}
