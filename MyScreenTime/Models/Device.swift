import Foundation
import SwiftData

@Model
final class Device {
    enum Kind: String, CaseIterable, Codable, Identifiable {
        case phone
        case tablet
        case computer
        case chromebook
        case television
        case gameConsole
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .phone: "Phone"
            case .tablet: "Tablet"
            case .computer: "Computer"
            case .chromebook: "Chromebook"
            case .television: "TV"
            case .gameConsole: "Game Console"
            case .other: "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .phone: "iphone"
            case .tablet: "ipad"
            case .computer: "desktopcomputer"
            case .chromebook: "laptopcomputer"
            case .television: "tv"
            case .gameConsole: "gamecontroller"
            case .other: "display"
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var name: String
    var kindRawValue: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var child: ChildProfile?
    @Relationship(deleteRule: .cascade, inverse: \UsageSession.device)
    var usageSessions: [UsageSession]

    var kind: Kind {
        get { Kind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        child: ChildProfile? = nil,
        usageSessions: [UsageSession] = []
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.kindRawValue = kind.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.child = child
        self.usageSessions = usageSessions
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidName(_ name: String) -> Bool {
        (2...50).contains(normalizedName(name).count)
    }
}
