import ActivityKit
import Foundation
import SwiftUI

/// Data shared between the BrightTime app and its widgets / Live Activities.
/// Compiled into both targets, so keep it free of app-only types.
enum SharedStore {
    static let appGroup = "group.com.karasandlabs.BrightTime"
    static let snapshotKey = "brighttime.widget.snapshot"
    static let widgetKind = "BrightTimeFamilyWidget"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

/// What the widgets show: one row per active child, written by the app whenever
/// usage, limits or timers change.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Child: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let colorHex: UInt32
        /// Minutes already recorded today (running timers not included).
        let usedMinutes: Int
        /// Today's limit, including any time added from the time bank.
        let limitMinutes: Int
        let bankMinutes: Int
        let timer: Timer?

        var initial: String {
            name.first.map { String($0).uppercased() } ?? "?"
        }
    }

    struct Timer: Codable, Equatable, Sendable {
        let deviceName: String
        let startedAt: Date
        let endsAt: Date
    }

    let generatedAt: Date
    /// When "today" ends (respects the Day resets at setting).
    let dayEndsAt: Date
    let children: [Child]

    static let empty = WidgetSnapshot(generatedAt: .now, dayEndsAt: .distantFuture, children: [])

    static func load() -> WidgetSnapshot? {
        guard let data = SharedStore.defaults.data(forKey: SharedStore.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SharedStore.defaults.set(data, forKey: SharedStore.snapshotKey)
    }
}

extension WidgetSnapshot.Child {
    /// Used minutes as of `date`, counting the part of a running timer that has
    /// already elapsed, so the widget stays right between app launches.
    func usedMinutes(at date: Date, dayEndsAt: Date) -> Int {
        guard date < dayEndsAt else { return 0 }
        guard let timer, date > timer.startedAt else { return usedMinutes }
        let elapsed = min(date, timer.endsAt).timeIntervalSince(timer.startedAt)
        return usedMinutes + Int(elapsed / 60)
    }

    func leftMinutes(at date: Date, dayEndsAt: Date) -> Int {
        limitMinutes - usedMinutes(at: date, dayEndsAt: dayEndsAt)
    }

    func runningTimer(at date: Date) -> WidgetSnapshot.Timer? {
        guard let timer, timer.endsAt > date else { return nil }
        return timer
    }

    var color: Color { Color(widgetHex: colorHex) }
}

/// The Live Activity shown on the Lock Screen and in the Dynamic Island while a
/// screen timer runs.
struct ScreenTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var startedAt: Date
        var endsAt: Date
    }

    var timerID: UUID
    var childName: String
    var deviceName: String
    var colorHex: UInt32

    var initial: String {
        childName.first.map { String($0).uppercased() } ?? "?"
    }
}

extension Color {
    init(widgetHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum WidgetTime {
    /// "1h 40m", "52m".
    static func compact(_ minutes: Int) -> String {
        let value = abs(minutes)
        let hours = value / 60
        let rest = value % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }
}
