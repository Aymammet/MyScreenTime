import Foundation
import SwiftData

/// Something a child can do to earn screen time, e.g. "Read for 30 min → +15 min".
@Model
final class EarnActivity {
    static let maximumNameLength = 24

    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "star.fill"
    var minutes: Int = 15
    var sortOrder: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        minutes: Int,
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.minutes = minutes
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Starter list shown the first time a parent opens "Earn time".
    static let starterSet: [(name: String, symbol: String, minutes: Int)] = [
        ("Reading", "book.fill", 15),
        ("Chores", "house.fill", 15),
        ("Homework done", "pencil.and.ruler.fill", 15),
        ("Outdoor play", "figure.run", 20),
        ("Practice", "music.note", 15),
        ("Helping out", "hands.sparkles.fill", 10),
    ]

    /// Symbols a parent can pick for a custom activity.
    static let symbolChoices = [
        "star.fill", "book.fill", "house.fill", "pencil.and.ruler.fill", "figure.run",
        "music.note", "hands.sparkles.fill", "bed.double.fill", "fork.knife", "leaf.fill",
        "dumbbell.fill", "paintbrush.fill", "pawprint.fill", "trash.fill", "tshirt.fill",
        "heart.fill",
    ]
}

/// One line in a child's time bank: minutes earned, or minutes taken out of the
/// bank and added to a day's limit.
@Model
final class TimeCredit {
    enum Kind: String, Codable {
        /// Minutes put into the bank (an activity or a bonus).
        case earned
        /// Minutes taken out of the bank and added to `day`'s limit.
        case used
    }

    var id: UUID = UUID()
    var kindRawValue: String = Kind.earned.rawValue
    /// Always positive; `kind` says which way it goes.
    var minutes: Int = 0
    var title: String = ""
    var symbol: String = "star.fill"
    /// For `.used`: the day whose limit grows. For `.earned`: when it was earned.
    var day: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var child: ChildProfile?

    var kind: Kind {
        get { Kind(rawValue: kindRawValue) ?? .earned }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        minutes: Int,
        title: String,
        symbol: String,
        day: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        child: ChildProfile? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.minutes = max(minutes, 0)
        self.title = title
        self.symbol = symbol
        self.day = day
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.child = child
    }
}

extension ChildProfile {
    /// Minutes waiting in the bank.
    var bankBalance: Int {
        let total = timeCredits.reduce(0) { sum, credit in
            sum + (credit.kind == .earned ? credit.minutes : -credit.minutes)
        }
        return max(total, 0)
    }

    /// Minutes from the bank added to `date`'s limit.
    func bonusMinutes(on date: Date, calendar: Calendar = AppCalendar.day) -> Int {
        timeCredits
            .filter { $0.kind == .used && calendar.isDate($0.day, inSameDayAs: date) }
            .reduce(0) { $0 + $1.minutes }
    }
}

/// A kid asking for extra time today ("+15 min?"). A parent approves or declines
/// it on this device or, with co-parent sync, from their own iPhone.
@Model
final class TimeRequest {
    enum Status: String, Codable {
        case pending, approved, denied
    }

    var id: UUID = UUID()
    /// Stored as an ID rather than a relationship, so a request can arrive
    /// through sync before its child does.
    var childID: UUID = UUID()
    var minutes: Int = 15
    var statusRawValue: String = Status.pending.rawValue
    /// The day the extra time is for.
    var day: Date = Date.now
    var createdAt: Date = Date.now
    var decidedAt: Date?
    var updatedAt: Date = Date.now

    var status: Status {
        get { Status(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        childID: UUID,
        minutes: Int,
        status: Status = .pending,
        day: Date = .now,
        createdAt: Date = .now,
        decidedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.childID = childID
        self.minutes = minutes
        self.statusRawValue = status.rawValue
        self.day = day
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.updatedAt = updatedAt
    }
}
