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
    }

    func timer(for childID: UUID) -> ActiveScreenTimer? {
        timers.first { $0.childID == childID }
    }

    func start(child: ChildProfile, device: Device, minutes: Int, now: Date = .now) {
        let timer = ActiveScreenTimer(
            id: UUID(),
            childID: child.id,
            childName: child.name,
            deviceID: device.id,
            deviceName: device.name,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60))
        )
        timers.removeAll { $0.childID == child.id }
        timers.append(timer)
        persist()
        Task { await scheduleNotification(for: timer) }
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
            context.insert(UsageSession(
                startedAt: timer.startedAt,
                endedAt: timer.endsAt,
                note: "Screen timer",
                child: child,
                device: device
            ))
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
        context.insert(UsageSession(
            startedAt: timer.startedAt,
            endedAt: stoppedAt,
            note: "Screen timer stopped",
            child: child,
            device: device
        ))
        remove(timer)
        try? context.save()
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
