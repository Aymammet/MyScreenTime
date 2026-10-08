import Foundation
import SwiftData

@Model
final class ParentProfile {
    static let maximumNameLength = 16

    @Attribute(.unique) var id: UUID
    var name: String
    var notificationsEnabled: Bool
    var timeZoneIdentifier: String
    var defaultAvatarRawValue: String?
    @Attribute(.externalStorage) var profilePhotoData: Data?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ChildProfile.parent)
    var children: [ChildProfile]

    init(
        id: UUID = UUID(),
        name: String,
        notificationsEnabled: Bool = true,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        defaultAvatar: DefaultProfileAvatar? = nil,
        profilePhotoData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        children: [ChildProfile] = []
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.notificationsEnabled = notificationsEnabled
        self.timeZoneIdentifier = timeZoneIdentifier
        self.defaultAvatarRawValue = defaultAvatar?.rawValue
        self.profilePhotoData = profilePhotoData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.children = children
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidName(_ name: String) -> Bool {
        (2...maximumNameLength).contains(normalizedName(name).count)
    }

    var defaultAvatar: DefaultProfileAvatar? {
        get { defaultAvatarRawValue.flatMap(DefaultProfileAvatar.init(rawValue:)) }
        set { defaultAvatarRawValue = newValue?.rawValue }
    }

    var resolvedDefaultAvatar: DefaultProfileAvatar {
        defaultAvatar ?? .boy1
    }
}
