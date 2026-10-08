import Foundation
import SwiftData

enum DefaultProfileAvatar: String, CaseIterable, Codable, Identifiable {
    case boy1, boy2, boy3, boy4, boy5
    case girl1, girl2, girl3, girl4, girl5

    var id: String { rawValue }

    var gender: ChildGender {
        rawValue.hasPrefix("boy") ? .boy : .girl
    }

    var assetName: String {
        switch self {
        case .boy1: "DefaultBoyAvatar"
        case .boy2: "DefaultBoyAvatar2"
        case .boy3: "DefaultBoyAvatar3"
        case .boy4: "DefaultBoyAvatar4"
        case .boy5: "DefaultBoyAvatar5"
        case .girl1: "DefaultGirlAvatar"
        case .girl2: "DefaultGirlAvatar2"
        case .girl3: "DefaultGirlAvatar3"
        case .girl4: "DefaultGirlAvatar4"
        case .girl5: "DefaultGirlAvatar5"
        }
    }

    var accessibilityName: String {
        "\(gender.title) avatar \((gender.avatarChoices.firstIndex(of: self) ?? 0) + 1)"
    }
}

enum ChildGender: String, CaseIterable, Codable, Identifiable {
    case boy
    case girl

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var avatarChoices: [DefaultProfileAvatar] {
        DefaultProfileAvatar.allCases.filter { $0.gender == self }
    }

    var defaultAvatarAssetName: String {
        avatarChoices[0].assetName
    }
}

@Model
final class ChildProfile {
    static let maximumNameLength = 16

    @Attribute(.unique) var id: UUID
    var name: String
    var dailyLimitMinutes: Int
    var weekdayLimitMinutes: Int?
    var weekendLimitMinutes: Int?
    @Attribute(.externalStorage) var profilePhotoData: Data?
    var genderRawValue: String?
    var defaultAvatarRawValue: String?
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
        gender: ChildGender? = nil,
        defaultAvatar: DefaultProfileAvatar? = nil,
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
        self.genderRawValue = gender?.rawValue
        self.defaultAvatarRawValue = defaultAvatar?.rawValue
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
        (2...maximumNameLength).contains(normalizedName(name).count)
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

    var gender: ChildGender? {
        get { genderRawValue.flatMap(ChildGender.init(rawValue:)) }
        set { genderRawValue = newValue?.rawValue }
    }

    /// Existing profiles predate gender selection. Give them a stable default
    /// avatar until the parent chooses a gender in Settings.
    var resolvedGender: ChildGender {
        if let gender { return gender }
        return id.uuidString.utf8.reduce(0, { $0 + Int($1) }).isMultiple(of: 2) ? .boy : .girl
    }

    var defaultAvatar: DefaultProfileAvatar? {
        get { defaultAvatarRawValue.flatMap(DefaultProfileAvatar.init(rawValue:)) }
        set { defaultAvatarRawValue = newValue?.rawValue }
    }

    var resolvedDefaultAvatar: DefaultProfileAvatar {
        if let defaultAvatar, defaultAvatar.gender == resolvedGender { return defaultAvatar }
        let choices = resolvedGender.avatarChoices
        let index = id.uuidString.utf8.reduce(0, { $0 + Int($1) }) % choices.count
        return choices[index]
    }

    /// A one-letter initial shown on the avatar when there's no profile photo.
    var initials: String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    private static func defaultColor(for id: UUID) -> ChildColor {
        // UUID bytes, not `hashValue`: Swift re-seeds hashes on every launch, which
        // made a child's default color change each time the app opened.
        let all = ChildColor.allCases
        return all[id.stableIndex(count: all.count)]
    }
}
