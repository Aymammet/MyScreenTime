import Foundation
import SwiftData

@Model
final class ParentProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var notificationsEnabled: Bool
    var timeZoneIdentifier: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ChildProfile.parent)
    var children: [ChildProfile]

    init(
        id: UUID = UUID(),
        name: String,
        notificationsEnabled: Bool = true,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        children: [ChildProfile] = []
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.notificationsEnabled = notificationsEnabled
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.children = children
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidName(_ name: String) -> Bool {
        (2...50).contains(normalizedName(name).count)
    }
}
