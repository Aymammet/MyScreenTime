import Foundation

enum AnalysisPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component {
        self == .week ? .weekOfYear : .month
    }
}

struct DailyUsagePoint: Identifiable, Equatable {
    let date: Date
    let minutes: Int
    var id: Date { date }
}

struct DeviceUsagePoint: Identifiable, Equatable {
    let deviceID: UUID
    let name: String
    let minutes: Int
    var id: UUID { deviceID }
}

struct PeriodAnalysis: Equatable {
    let currentMinutes: Int
    let previousMinutes: Int
    let dailyAverageMinutes: Int
    let dailyPoints: [DailyUsagePoint]
    let devicePoints: [DeviceUsagePoint]

    var changePercent: Int? {
        guard previousMinutes > 0 else { return nil }
        return Int(((Double(currentMinutes - previousMinutes) / Double(previousMinutes)) * 100).rounded())
    }
}

enum AnalysisCalculator {
    static func analyze(
        period: AnalysisPeriod,
        now: Date,
        childIDs: Set<UUID>,
        sessions: [UsageSession],
        devices: [Device],
        calendar: Calendar = .current
    ) -> PeriodAnalysis {
        guard let currentFull = calendar.dateInterval(of: period.calendarComponent, for: now),
              let previousReference = calendar.date(byAdding: .second, value: -1, to: currentFull.start),
              let previousFull = calendar.dateInterval(of: period.calendarComponent, for: previousReference) else {
            return PeriodAnalysis(currentMinutes: 0, previousMinutes: 0, dailyAverageMinutes: 0, dailyPoints: [], devicePoints: [])
        }

        let todayStart = calendar.startOfDay(for: now)
        let elapsedDayCount = max((calendar.dateComponents([.day], from: currentFull.start, to: todayStart).day ?? 0) + 1, 1)
        let currentEnd = min(calendar.date(byAdding: .day, value: 1, to: todayStart) ?? currentFull.end, currentFull.end)
        let previousEnd = min(calendar.date(byAdding: .day, value: elapsedDayCount, to: previousFull.start) ?? previousFull.end, previousFull.end)
        let currentInterval = DateInterval(start: currentFull.start, end: currentEnd)
        let previousInterval = DateInterval(start: previousFull.start, end: previousEnd)
        let currentMinutes = UsageAggregator.totalMinutes(in: currentInterval, childIDs: childIDs, sessions: sessions)
        let previousMinutes = UsageAggregator.totalMinutes(in: previousInterval, childIDs: childIDs, sessions: sessions)

        var dailyPoints: [DailyUsagePoint] = []
        for offset in 0..<elapsedDayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: currentFull.start),
                  let interval = calendar.dateInterval(of: .day, for: day) else { continue }
            dailyPoints.append(DailyUsagePoint(
                date: day,
                minutes: UsageAggregator.totalMinutes(in: interval, childIDs: childIDs, sessions: sessions)
            ))
        }

        let devicePoints = devices.compactMap { device -> DeviceUsagePoint? in
            let minutes = sessions
                .filter {
                    guard let sessionChildID = $0.child?.id else { return false }
                    return childIDs.contains(sessionChildID)
                        && $0.device?.id == device.id
                        && $0.startedAt >= currentInterval.start
                        && $0.startedAt < currentInterval.end
                }
                .reduce(0) { $0 + $1.durationMinutes }
            return minutes > 0 ? DeviceUsagePoint(deviceID: device.id, name: device.name, minutes: minutes) : nil
        }
        .sorted { $0.minutes > $1.minutes }

        return PeriodAnalysis(
            currentMinutes: currentMinutes,
            previousMinutes: previousMinutes,
            dailyAverageMinutes: currentMinutes / elapsedDayCount,
            dailyPoints: dailyPoints,
            devicePoints: devicePoints
        )
    }
}
