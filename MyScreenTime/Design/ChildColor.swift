import SwiftUI

/// A curated set of identity colors a parent can assign to each child, so kids are
/// told apart at a glance (avatar) independent of their daily limit status (ring).
enum ChildColor: String, CaseIterable, Identifiable, Codable {
    case teal
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .teal: Color(red: 0.184, green: 0.435, blue: 0.420)
        case .blue: Color(red: 0.243, green: 0.463, blue: 0.925)
        case .indigo: Color(red: 0.365, green: 0.361, blue: 0.902)
        case .purple: Color(red: 0.545, green: 0.361, blue: 0.965)
        case .pink: Color(red: 0.886, green: 0.345, blue: 0.564)
        case .red: Color(red: 0.882, green: 0.357, blue: 0.322)
        case .orange: Color(red: 0.902, green: 0.529, blue: 0.184)
        case .yellow: Color(red: 0.812, green: 0.647, blue: 0.129)
        case .green: Color(red: 0.247, green: 0.604, blue: 0.431)
        case .slate: Color(red: 0.318, green: 0.365, blue: 0.427)
        }
    }

    var displayName: String { rawValue.capitalized }
}
