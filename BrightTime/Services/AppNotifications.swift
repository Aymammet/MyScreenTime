import Foundation
import Observation
import SwiftData
import UserNotifications

/// Screens a notification tap can open.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Destination: Equatable {
        case recap
        case requests
    }

    /// Opened once the app is unlocked, then cleared.
    var pending: Destination?

    private init() {}
}

/// Local notifications beyond timers: time requests (with Approve / Not now
/// buttons) and the Sunday recap.
@MainActor
final class AppNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotifications()

    static let requestCategory = "brighttime.time-request"
    static let approveAction = "brighttime.approve"
    static let denyAction = "brighttime.deny"
    static let recapID = "brighttime.weekly-recap"
    static let recapEnabledKey = "brighttime.recap.enabled"

    static var isRecapEnabled: Bool {
        UserDefaults.standard.object(forKey: recapEnabledKey) as? Bool ?? true
    }

    private override init() {}

    /// Call once at launch.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let approve = UNNotificationAction(identifier: Self.approveAction, title: "Approve", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: Self.denyAction, title: "Not now", options: [.authenticationRequired])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.requestCategory, actions: [approve, deny], intentIdentifiers: []),
        ])
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func canNotify() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: - Time requests

    /// A request created, approved or declined on another device just synced in.
    func requestArrivedFromSync(_ request: TimeRequest, context: ModelContext) {
        guard AppCalendar.day.isDate(request.day, inSameDayAs: .now) else { return }
        let childID = request.childID
        let name = (try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == childID })).first?.name) ?? "Your kid"
        let minutes = TimeText.compact(request.minutes)

        if let kidID = KidMode.childID {
            // This device is the kid's: tell them the answer.
            guard kidID == request.childID, request.status != .pending else { return }
            post(
                id: "request-\(request.id.uuidString)",
                title: request.status == .approved ? "Yes! +\(minutes) added" : "Not this time",
                body: request.status == .approved ? "A parent approved your extra time for today." : "A parent said not now. You can ask again later.",
                category: nil,
                userInfo: [:]
            )
        } else if request.status == .pending {
            post(
                id: "request-\(request.id.uuidString)",
                title: "\(name) asks for more time",
                body: "+\(minutes) today. Approve, or say not now.",
                category: Self.requestCategory,
                userInfo: ["requestID": request.id.uuidString]
            )
        } else {
            // Another parent already answered.
            removeRequestNotification(for: request.id)
        }
    }

    func removeRequestNotification(for id: UUID) {
        let identifier = "request-\(id.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func post(id: String, title: String, body: String, category: String?, userInfo: [String: String]) {
        Task {
            guard await canNotify() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let category { content.categoryIdentifier = category }
            content.userInfo = userInfo
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id, content: content, trigger: nil)
            )
        }
    }

    // MARK: - Sunday recap

    /// Keeps one repeating "your week" notification for Sunday at 6 PM, or none
    /// when the parent turned it (or notifications) off.
    func rescheduleRecap(kidNames: [String], notificationsOn: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.recapID])
        guard notificationsOn, Self.isRecapEnabled, !kidNames.isEmpty, !KidMode.isActive else { return }
        Task {
            guard await canNotify() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your week in BrightTime"
            let names = ListFormatter.localizedString(byJoining: kidNames)
            content.body = "See how \(names) did this week: totals, streaks and the best day."
            content.sound = .default
            content.userInfo = ["route": "recap"]
            var when = DateComponents()
            when.weekday = 1
            when.hour = 18
            when.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: Self.recapID, content: content, trigger: trigger))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let requestID = (info["requestID"] as? String).flatMap(UUID.init(uuidString:))
        let route = info["route"] as? String
        await handle(action: action, requestID: requestID, route: route)
    }

    private func handle(action: String, requestID: UUID?, route: String?) {
        if let requestID {
            let context = AppServices.shared.context
            let request = try? context.fetch(FetchDescriptor<TimeRequest>(predicate: #Predicate { $0.id == requestID })).first
            switch action {
            case Self.approveAction:
                if let request { KidRequests.approve(request, context: context) }
                Task { await FamilySync.shared.syncNow(quiet: true) }
            case Self.denyAction:
                if let request { KidRequests.deny(request, context: context) }
                Task { await FamilySync.shared.syncNow(quiet: true) }
            default:
                AppRouter.shared.pending = .requests
            }
        } else if route == "recap" {
            AppRouter.shared.pending = .recap
        }
    }
}
