import Foundation
import WidgetKit

/// Writes what the Home / Lock Screen widgets show into the shared App Group and
/// asks WidgetKit to redraw them.
@MainActor
enum WidgetSnapshotWriter {
    static func write(children: [ChildProfile], sessions: [UsageSession], timers: [ActiveScreenTimer]) {
        let calendar = AppCalendar.day
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .distantFuture

        let rows = children.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }.map { child in
            let summary = UsageAggregator.summary(on: .now, child: child, sessions: sessions, calendar: calendar)
            let timer = timers.first { $0.childID == child.id }
            return WidgetSnapshot.Child(
                id: child.id,
                name: child.name,
                colorHex: child.color.hex,
                usedMinutes: summary.usedMinutes,
                limitMinutes: summary.limitMinutes,
                bankMinutes: child.bankBalance,
                timer: timer.map {
                    WidgetSnapshot.Timer(deviceName: $0.deviceName, startedAt: $0.startedAt, endsAt: $0.endsAt)
                }
            )
        }

        let previous = WidgetSnapshot.load()
        guard previous?.children != rows || previous?.dayEndsAt != end else { return }

        WidgetSnapshot(generatedAt: .now, dayEndsAt: end, children: rows).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
