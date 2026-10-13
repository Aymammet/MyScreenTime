import Foundation
import SwiftData
import UIKit

/// Someone typed the wrong parent passcode several times in a row. Shown to
/// parents on Home and, with co-parent sharing, sent to the other parent's
/// iPhone as a notification.
@Model
final class PasscodeAlert {
    var id: UUID = UUID()
    /// Wrong tries in this run, updated as more come in.
    var attempts: Int = 0
    var firstAt: Date = Date.now
    var lastAt: Date = Date.now
    /// "Anar's iPhone" or "Emir's iPad (kid mode)".
    var deviceLabel: String = ""
    /// Which device it happened on, so that device doesn't notify itself.
    var deviceID: String = ""
    var acknowledged: Bool = false
    var updatedAt: Date = Date.now

    init(attempts: Int, deviceLabel: String, deviceID: String, at date: Date = .now) {
        self.attempts = attempts
        self.firstAt = date
        self.lastAt = date
        self.deviceLabel = deviceLabel
        self.deviceID = deviceID
        self.updatedAt = date
    }
}

@MainActor
enum PasscodeAlerts {
    /// Wrong tries in a row before parents are told.
    static let threshold = 3

    private static let currentKey = "brighttime.passcodeAlert.current"

    static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    /// Called by AppLock after each wrong passcode with the running count.
    static func recordFailure(count: Int, now: Date = .now) {
        guard count >= threshold, !AppServices.shared.isUITesting else { return }
        let context = AppServices.shared.context

        if let current = currentAlert(in: context) {
            current.attempts = count
            current.lastAt = now
            current.updatedAt = now
            current.acknowledged = false
        } else {
            let alert = PasscodeAlert(attempts: count, deviceLabel: deviceLabel(in: context), deviceID: deviceID, at: now)
            context.insert(alert)
            UserDefaults.standard.set(alert.id.uuidString, forKey: currentKey)
        }
        try? context.save()
        // Get it to the other parent's iPhone right away.
        Task { await FamilySync.shared.syncNow(quiet: true) }
    }

    /// A correct passcode (or unlock) ends the run; the next wrong try starts a new alert.
    static func endRun() {
        UserDefaults.standard.removeObject(forKey: currentKey)
    }

    static func acknowledge(_ alert: PasscodeAlert, context: ModelContext) {
        alert.acknowledged = true
        alert.updatedAt = .now
        try? context.save()
        AppNotifications.shared.removePasscodeNotification(for: alert.id)
    }

    private static func currentAlert(in context: ModelContext) -> PasscodeAlert? {
        guard let raw = UserDefaults.standard.string(forKey: currentKey),
              let id = UUID(uuidString: raw) else { return nil }
        return try? context.fetch(FetchDescriptor<PasscodeAlert>(predicate: #Predicate { $0.id == id })).first
    }

    private static func deviceLabel(in context: ModelContext) -> String {
        let model = UIDevice.current.model
        if let kidID = KidMode.childID,
           let kid = try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == kidID })).first {
            return "\(kid.name)'s \(model) (kid mode)"
        }
        if let parent = try? context.fetch(FetchDescriptor<ParentProfile>(sortBy: [SortDescriptor(\.createdAt)])).first {
            return "\(parent.name)'s \(model)"
        }
        return "this \(model)"
    }
}
