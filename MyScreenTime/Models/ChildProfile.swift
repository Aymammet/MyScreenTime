import Foundation
import SwiftData

@Model
final class ChildProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var dailyLimitMinutes: Int
    var weekdayLimitMinutes: Int?
    var weekendLimitMinutes: Int?
    @Attribute(.externalStorage) var profilePhotoData: Data?
    var colorRawValue: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var parent: ParentProfile?
    @Relationship(deleteRule: .cascade, inverse: \Device.child)
    var devices: [Device]
    @Relationship(deleteRule: .cascade, inverse: \UsageSession.child)
    var usageSessions: [UsageSession]

    init(
        id: UUID = UUID(),
        name: String,
        dailyLimitMinutes: Int = 120,
        weekdayLimitMinutes: Int? = nil,
        weekendLimitMinutes: Int? = nil,
        profilePhotoData: Data? = nil,
        colorRawValue: String? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        parent: ParentProfile? = nil,
        devices: [Device] = [],
        usageSessions: [UsageSession] = []
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.dailyLimitMinutes = dailyLimitMinutes
        self.weekdayLimitMinutes = weekdayLimitMinutes
        self.weekendLimitMinutes = weekendLimitMinutes
        self.profilePhotoData = profilePhotoData
        self.colorRawValue = colorRawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parent = parent
        self.devices = devices
        self.usageSessions = usageSessions
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidName(_ name: String) -> Bool {
        (2...50).contains(normalizedName(name).count)
    }

    static func isValidDailyLimit(_ minutes: Int) -> Bool {
        (15...1_440).contains(minutes) && minutes.isMultiple(of: 15)
    }

    var formattedDailyLimit: String {
        Self.formattedLimit(dailyLimitMinutes)
    }

    func limitMinutes(on date: Date, calendar: Calendar = .current) -> Int {
        guard let weekdayLimitMinutes, let weekendLimitMinutes else {
            return dailyLimitMinutes
        }

        return calendar.isDateInWeekend(date) ? weekendLimitMinutes : weekdayLimitMinutes
    }

    func formattedLimit(on date: Date, calendar: Calendar = .current) -> String {
        Self.formattedLimit(limitMinutes(on: date, calendar: calendar))
    }

    private static func formattedLimit(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if minutes == 0 {
            return "\(hours) hr"
        }

        return "\(hours) hr \(minutes) min"
    }

    /// The child's identity color, used for their avatar so siblings are told apart
    /// at a glance. Falls back to a color chosen deterministically from the child's
    /// id when none has been picked yet, so every child always has a stable color.
    var color: ChildColor {
        get { colorRawValue.flatMap(ChildColor.init(rawValue:)) ?? Self.defaultColor(for: id) }
        set { colorRawValue = newValue.rawValue }
    }

    /// A one-letter initial shown on the avatar when there's no profile photo.
    var initials: String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    private static func defaultColor(for id: UUID) -> ChildColor {
        let all = ChildColor.allCases
        return all[abs(id.hashValue) % all.count]
    }
}
