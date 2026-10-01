import Foundation
import SwiftData

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

    /// A short, human status headline used above progress rings on the dashboard and child detail screens.
    var headline: String {
        switch status {
        case .normal: "On track today"
        case .nearLimit: "Near limit"
        case .reached: "Limit reached"
        case .exceeded: "\(UsageAggregator.format(minutes: overMinutes)) over limit"
        }
    }

    /// A compact "N min left" / "N min over" label used next to progress rings.
    var remainingHeadline: String {
        overMinutes > 0
            ? "\(UsageAggregator.format(minutes: overMinutes)) over"
            : "\(UsageAggregator.format(minutes: remainingMinutes)) left"
    }
}

enum UsageAggregator {
    static func totalMinutes(
        in interval: DateInterval,
        childIDs: Set<UUID>,
        sessions: [UsageSession]
    ) -> Int {
        sessions
            .filter { session in
                guard let childID = session.child?.id else { return false }
                return childIDs.contains(childID)
                    && session.startedAt >= interval.start
                    && session.startedAt < interval.end
            }
            .reduce(0) { $0 + $1.durationMinutes }
    }

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

    static func totalMinutes(
        on day: Date,
        childID: UUID,
        deviceID: UUID,
        sessions: [UsageSession],
        calendar: Calendar = .current
    ) -> Int {
        sessions
            .filter { session in
                session.child?.id == childID
                    && session.device?.id == deviceID
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

/// Adds deterministic demo history for the seven completed days before today.
/// Existing days are left untouched, so relaunching the app never duplicates usage.
@MainActor
enum SampleUsageSeeder {
    private static let sampleNote = "BrightTime sample history"
    private static let minuteChoices = [20, 30, 40, 55, 70, 85, 105, 130, 160, 210]

    @discardableResult
    static func seedPreviousWeekIfNeeded(
        children: [ChildProfile],
        devices: [Device],
        existingSessions: [UsageSession],
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Int {
        var sessions = existingSessions
        var insertedCount = 0
        var didChange = false

        for (childIndex, child) in children.filter(\.isActive).enumerated() {
            var availableDevices = devices
                .filter { $0.isActive && $0.isAvailable(to: child.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Zeynep's requested sample needs a Chromebook; add a personal one when the
            // development profile does not have one yet.
            if child.name.caseInsensitiveCompare("Zeynep") == .orderedSame,
               !availableDevices.contains(where: {
                   $0.kind == .chromebook || $0.name.localizedCaseInsensitiveContains("chromebook")
               }) {
                let chromebook = Device(name: "Chromebook", kind: .chromebook, child: child)
                context.insert(chromebook)
                availableDevices.append(chromebook)
                didChange = true
            }

            guard !availableDevices.isEmpty else { continue }

            for daysAgo in 1...7 {
                guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }

                let existingSession = sessions.first(where: {
                    $0.child?.id == child.id && calendar.isDate($0.startedAt, inSameDayAs: date)
                })

                // Preserve manually entered history. If this is one of our own sample
                // rows, keep the requested anchor examples exact across app updates.
                if let existingSession {
                    guard existingSession.note == sampleNote else { continue }
                    if applyRequestedAnchor(
                        to: existingSession,
                        child: child,
                        daysAgo: daysAgo,
                        devices: availableDevices,
                        calendar: calendar
                    ) {
                        didChange = true
                    }
                    continue
                }

                var device = availableDevices[(childIndex + daysAgo - 1) % availableDevices.count]
                var minutes = minuteChoices[stableIndex(for: child, daysAgo: daysAgo) % minuteChoices.count]

                // Requested anchor examples, applied whenever the named child/device exists.
                switch (child.name.lowercased(), daysAgo) {
                case ("kevin", 1):
                    if let ps5 = availableDevices.first(where: { $0.name.localizedCaseInsensitiveContains("ps5") }) {
                        device = ps5
                        minutes = 35
                    }
                case ("zeynep", 3):
                    if let chromebook = availableDevices.first(where: {
                        $0.kind == .chromebook || $0.name.localizedCaseInsensitiveContains("chromebook")
                    }) {
                        device = chromebook
                        minutes = 45
                    }
                case ("ali", 2):
                    if let tcl = availableDevices.first(where: { $0.name.localizedCaseInsensitiveContains("tcl") }) {
                        device = tcl
                        minutes = 300
                    }
                default:
                    break
                }

                let dayStart = calendar.startOfDay(for: date)
                let startHour = 9 + ((childIndex * 2 + daysAgo) % 7)
                guard let startedAt = calendar.date(byAdding: .hour, value: startHour, to: dayStart),
                      let endedAt = calendar.date(byAdding: .minute, value: minutes, to: startedAt) else { continue }

                let session = UsageSession(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: sampleNote,
                    child: child,
                    device: device
                )
                context.insert(session)
                sessions.append(session)
                insertedCount += 1
                didChange = true
            }
        }

        if didChange {
            try context.save()
        }
        return insertedCount
    }

    private static func applyRequestedAnchor(
        to session: UsageSession,
        child: ChildProfile,
        daysAgo: Int,
        devices: [Device],
        calendar: Calendar
    ) -> Bool {
        let requested: (device: Device, minutes: Int)?

        switch (child.name.lowercased(), daysAgo) {
        case ("kevin", 1):
            requested = devices.first(where: { $0.name.localizedCaseInsensitiveContains("ps5") }).map { ($0, 35) }
        case ("zeynep", 3):
            requested = devices.first(where: {
                $0.kind == .chromebook || $0.name.localizedCaseInsensitiveContains("chromebook")
            }).map { ($0, 45) }
        case ("ali", 2):
            requested = devices.first(where: { $0.name.localizedCaseInsensitiveContains("tcl") }).map { ($0, 300) }
        default:
            requested = nil
        }

        guard let requested,
              let endedAt = calendar.date(byAdding: .minute, value: requested.minutes, to: session.startedAt) else {
            return false
        }

        let needsUpdate = session.device?.id != requested.device.id || session.durationMinutes != requested.minutes
        guard needsUpdate else { return false }
        session.device = requested.device
        session.endedAt = endedAt
        session.updatedAt = .now
        return true
    }

    private static func stableIndex(for child: ChildProfile, daysAgo: Int) -> Int {
        child.name.lowercased().utf8.reduce(daysAgo * 31) { partial, byte in
            (partial &* 17 &+ Int(byte)) % 10_000
        }
    }
}
