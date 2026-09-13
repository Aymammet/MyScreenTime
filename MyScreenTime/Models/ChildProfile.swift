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
}
