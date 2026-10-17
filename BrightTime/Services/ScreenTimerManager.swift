import Foundation
import Combine
import SwiftData
import UserNotifications

struct ActiveScreenTimer: Codable, Identifiable, Equatable {
    let id: UUID
    let childID: UUID
    let childName: String
    let deviceID: UUID
    let deviceName: String
    let startedAt: Date
    let endsAt: Date
    /// The child's color for the Live Activity (missing on timers saved by older builds).
    var childColorHex: UInt32?
    /// Optional for compatibility with timers saved before per-timer controls existed.
    var notifyWhenFinished: Bool?
    var showOnLockScreen: Bool?

    var shouldNotifyWhenFinished: Bool { notifyWhenFinished ?? true }
    var shouldShowOnLockScreen: Bool { showOnLockScreen ?? true }

    var durationMinutes: Int {
        max(Int(endsAt.timeIntervalSince(startedAt) / 60), 1)
    }
}

@MainActor
final class ScreenTimerManager: ObservableObject {
    @Published private(set) var timers: [ActiveScreenTimer] = []

    private let storageKey = "active-screen-timers"

    init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([ActiveScreenTimer].self, from: data) else { return }
        timers = saved
        LiveActivityController.sync(with: timers)
    }

    func timer(for childID: UUID) -> ActiveScreenTimer? {
        timers.first { $0.childID == childID }
    }

    @discardableResult
    func start(
        child: ChildProfile,
        device: Device,
        minutes: Int,
        notifyWhenFinished: Bool = true,
        showOnLockScreen: Bool = true,
        now: Date = .now
    ) -> ActiveScreenTimer {
        let timer = ActiveScreenTimer(
            id: UUID(),
            childID: child.id,
            childName: child.name,
            deviceID: device.id,
            deviceName: device.name,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
            childColorHex: child.color.hex,
            notifyWhenFinished: notifyWhenFinished,
            showOnLockScreen: showOnLockScreen
        )
        let replaced = timers.filter { $0.childID == child.id }.map(\.id.uuidString)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: replaced)
        timers.removeAll { $0.childID == child.id }
        timers.append(timer)
        persist()
        if notifyWhenFinished {
            Task { await scheduleNotification(for: timer) }
        }
        return timer
    }

    func completeDueTimers(
        now: Date = .now,
        children: [ChildProfile],
        devices: [Device],
        context: ModelContext
    ) {
        let completed = timers.filter { $0.endsAt <= now }
        guard !completed.isEmpty else { return }

        for timer in completed {
            guard let child = children.first(where: { $0.id == timer.childID }),
                  let device = devices.first(where: { $0.id == timer.deviceID }) else { continue }
            insertUsage(from: timer.startedAt, to: timer.endsAt, note: "Screen timer", child: child, device: device, context: context)
        }
        timers.removeAll { $0.endsAt <= now }
        persist()
        try? context.save()
    }

    func stop(
        _ timer: ActiveScreenTimer,
        now: Date = .now,
        children: [ChildProfile],
        devices: [Device],
        context: ModelContext
    ) {
        guard let child = children.first(where: { $0.id == timer.childID }),
              let device = devices.first(where: { $0.id == timer.deviceID }) else {
            remove(timer)
            return
        }

        let stoppedAt = min(max(now, timer.startedAt.addingTimeInterval(1)), timer.endsAt)
        insertUsage(from: timer.startedAt, to: stoppedAt, note: "Screen timer stopped", child: child, device: device, context: context)
        remove(timer)
        try? context.save()
    }

    /// Stops and records any running timer for a child (e.g. before archiving them).
    func stopTimer(
        forChildID childID: UUID,
        children: [ChildProfile],
        devices: [Device],
        context: ModelContext
    ) {
        guard let timer = timer(for: childID) else { return }
        stop(timer, children: children, devices: devices, context: context)
    }

    /// Stops and records every running timer that uses a device before that
    /// device is removed from active use.
    func stopTimers(
        forDeviceID deviceID: UUID,
        children: [ChildProfile],
        devices: [Device],
        context: ModelContext
    ) {
        let matchingTimers = timers.filter { $0.deviceID == deviceID }
        for timer in matchingTimers {
            stop(timer, children: children, devices: devices, context: context)
        }
    }

    /// Drops every timer and its notification (used by Reset BrightTime).
    func clearAll() {
        let ids = timers.map(\.id.uuidString)
        timers.removeAll()
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Records timer time, skipping any minutes already covered by a saved session
    /// for the same child, so a timer and a manual entry never count twice.
    private func insertUsage(
        from start: Date,
        to end: Date,
        note: String,
        child: ChildProfile,
        device: Device,
        context: ModelContext
    ) {
        guard end > start else { return }
        let descriptor = FetchDescriptor<UsageSession>(
            predicate: #Predicate { $0.startedAt < end && $0.endedAt > start }
        )
        let busy = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.child?.id == child.id }
            .map { (start: $0.startedAt, end: $0.endedAt) }

        for segment in Self.uncoveredSegments(from: start, to: end, excluding: busy)
        where segment.end.timeIntervalSince(segment.start) >= 60 {
            context.insert(UsageSession(
                startedAt: segment.start,
                endedAt: segment.end,
                note: note,
                child: child,
                device: device
            ))
        }
    }

    /// The parts of `start...end` not covered by any `busy` interval.
    nonisolated static func uncoveredSegments(
        from start: Date,
        to end: Date,
        excluding busy: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        var segments: [(start: Date, end: Date)] = []
        var cursor = start
        for interval in busy.sorted(by: { $0.start < $1.start }) {
            if interval.end <= cursor { continue }
            if interval.start >= end { break }
            if interval.start > cursor {
                segments.append((start: cursor, end: min(interval.start, end)))
            }
            cursor = max(cursor, interval.end)
            if cursor >= end { break }
        }
        if cursor < end {
            segments.append((start: cursor, end: end))
        }
        return segments
    }

    private func remove(_ timer: ActiveScreenTimer) {
        timers.removeAll { $0.id == timer.id }
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [timer.id.uuidString]
        )
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        LiveActivityController.sync(with: timers)
    }

    private func scheduleNotification(for timer: ActiveScreenTimer) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Screen time is over"
        content.body = "Your \(timer.durationMinutes) min \(timer.deviceName) time for \(timer.childName) is over."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(timer.endsAt.timeIntervalSinceNow, 1),
            repeats: false
        )
        try? await center.add(UNNotificationRequest(
            identifier: timer.id.uuidString,
            content: content,
            trigger: trigger
        ))
    }
}
