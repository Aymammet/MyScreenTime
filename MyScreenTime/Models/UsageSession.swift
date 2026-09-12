import Foundation
import SwiftData

@Model
final class UsageSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var child: ChildProfile?
    var device: Device?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        child: ChildProfile? = nil,
        device: Device? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.child = child
        self.device = device
    }

    var durationMinutes: Int {
        (try? DurationCalculator.minutes(from: startedAt, to: endedAt)) ?? 0
    }

    var formattedDuration: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60

        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    static func hasOverlap(
        startedAt proposedStart: Date,
        endedAt proposedEnd: Date,
        childID: UUID,
        excluding sessionID: UUID? = nil,
        among sessions: [UsageSession]
    ) -> Bool {
        sessions.contains { session in
            session.child?.id == childID
                && session.id != sessionID
                && proposedStart < session.endedAt
                && proposedEnd > session.startedAt
        }
    }
}
