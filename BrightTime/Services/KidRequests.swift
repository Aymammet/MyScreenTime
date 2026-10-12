import Foundation
import SwiftData

/// "Ask for more time": kids ask, parents approve or decline.
///
/// An approved request adds the minutes to today's limit. It's written as two
/// time-bank lines (earned + used), so the bank balance doesn't change and the
/// extra time syncs like any other time-bank entry.
@MainActor
enum KidRequests {
    static let choices = [15, 30]
    /// Title of the time-bank lines an approved request writes.
    static let extraTimeTitle = "Extra time from a parent"

    /// The kid's open request for today, if any.
    static func pending(for childID: UUID, in context: ModelContext, now: Date = .now) -> TimeRequest? {
        allPending(in: context, now: now).first { $0.childID == childID }
    }

    /// Every open request for today, oldest first.
    static func allPending(in context: ModelContext, now: Date = .now) -> [TimeRequest] {
        let pending = TimeRequest.Status.pending.rawValue
        let descriptor = FetchDescriptor<TimeRequest>(
            predicate: #Predicate { $0.statusRawValue == pending },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let calendar = AppCalendar.day
        return ((try? context.fetch(descriptor)) ?? []).filter { calendar.isDate($0.day, inSameDayAs: now) }
    }

    @discardableResult
    static func ask(child: ChildProfile, minutes: Int, context: ModelContext, now: Date = .now) -> TimeRequest {
        if let open = pending(for: child.id, in: context, now: now) {
            open.minutes = minutes
            open.updatedAt = now
            try? context.save()
            return open
        }
        let request = TimeRequest(childID: child.id, minutes: minutes, day: now, createdAt: now, updatedAt: now)
        context.insert(request)
        try? context.save()
        return request
    }

    static func cancel(_ request: TimeRequest, context: ModelContext) {
        AppNotifications.shared.removeRequestNotification(for: request.id)
        context.delete(request)
        try? context.save()
    }

    static func approve(_ request: TimeRequest, context: ModelContext, now: Date = .now) {
        guard request.status == .pending else { return }
        request.status = .approved
        request.decidedAt = now
        request.updatedAt = now

        let childID = request.childID
        let child = try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == childID })).first
        if let child {
            let title = extraTimeTitle
            context.insert(TimeCredit(kind: .earned, minutes: request.minutes, title: title, symbol: "hand.thumbsup.fill", day: now, child: child))
            context.insert(TimeCredit(kind: .used, minutes: request.minutes, title: title, symbol: "hand.thumbsup.fill", day: request.day, child: child))
        }
        try? context.save()
        AppNotifications.shared.removeRequestNotification(for: request.id)
    }

    static func deny(_ request: TimeRequest, context: ModelContext, now: Date = .now) {
        guard request.status == .pending else { return }
        request.status = .denied
        request.decidedAt = now
        request.updatedAt = now
        try? context.save()
        AppNotifications.shared.removeRequestNotification(for: request.id)
    }

    /// The latest answer a kid got today, to show on their screen.
    static func latestAnswer(for childID: UUID, in context: ModelContext, now: Date = .now) -> TimeRequest? {
        let descriptor = FetchDescriptor<TimeRequest>(
            predicate: #Predicate { $0.childID == childID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let calendar = AppCalendar.day
        return ((try? context.fetch(descriptor)) ?? []).first {
            $0.status != .pending && calendar.isDate($0.day, inSameDayAs: now)
        }
    }
}

/// Which kid this device is handed to, if any. While set, BrightTime shows only
/// that kid's screen; leaving it needs the parent passcode or Face ID.
enum KidMode {
    static let storageKey = "brighttime.kidMode.childID"

    static var childID: UUID? {
        UserDefaults.standard.string(forKey: storageKey).flatMap(UUID.init(uuidString:))
    }

    static var isActive: Bool { childID != nil }
}
