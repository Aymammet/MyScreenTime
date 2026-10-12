@preconcurrency import ActivityKit
import Foundation

/// Keeps one Live Activity (Lock Screen + Dynamic Island) per running screen timer.
@MainActor
enum LiveActivityController {
    static func sync(with timers: [ActiveScreenTimer], now: Date = .now) {
        let activities = Activity<ScreenTimerAttributes>.activities
        let liveTimerIDs = Set(timers.filter { $0.endsAt > now }.map(\.id))

        for activity in activities where !liveTimerIDs.contains(activity.attributes.timerID) {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let shownTimerIDs = Set(activities.map(\.attributes.timerID))

        for timer in timers where timer.endsAt > now && !shownTimerIDs.contains(timer.id) {
            let attributes = ScreenTimerAttributes(
                timerID: timer.id,
                childName: timer.childName,
                deviceName: timer.deviceName,
                colorHex: timer.childColorHex ?? 0x2F8F8A
            )
            let state = ScreenTimerAttributes.ContentState(startedAt: timer.startedAt, endsAt: timer.endsAt)
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: timer.endsAt),
                pushType: nil
            )
        }
    }
}
