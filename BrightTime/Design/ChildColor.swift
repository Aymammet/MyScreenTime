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
        case .teal: Color(red: 0.184, green: 0.561, blue: 0.541)
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

    /// Same color as a 0xRRGGBB value, for widgets and Live Activities.
    var hex: UInt32 {
        switch self {
        case .teal: 0x2F8F8A
        case .blue: 0x3E76EC
        case .indigo: 0x5D5CE6
        case .purple: 0x8B5CF6
        case .pink: 0xE25890
        case .red: 0xE15B52
        case .orange: 0xE6872F
        case .yellow: 0xCFA521
        case .green: 0x3F9A6E
        case .slate: 0x515D6D
        }
    }
}
