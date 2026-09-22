import SwiftUI

enum AppTheme {
    // Core brand color — a calm teal that reads as "trustworthy" without borrowing
    // the generic system indigo/blue used by most iOS apps.
    static let primary = Color(red: 0.184, green: 0.435, blue: 0.420)
    static let primaryTint = Color(red: 0.902, green: 0.945, blue: 0.937)

    // Status colors. These intentionally never overlap the device palette below,
    // so a color can only ever mean "limit status" or "which device" — never both.
    static let success = Color(red: 0.247, green: 0.604, blue: 0.431)
    static let successTint = Color(red: 0.902, green: 0.961, blue: 0.929)
    static let warning = Color(red: 0.871, green: 0.604, blue: 0.235)
    static let warningTint = Color(red: 0.984, green: 0.941, blue: 0.875)
    static let danger = Color(red: 0.882, green: 0.357, blue: 0.322)
    static let dangerTint = Color(red: 0.984, green: 0.906, blue: 0.898)

    // Neutral surfaces used for the card-based layout.
    static let background = Color(red: 0.949, green: 0.957, blue: 0.969)
    static let surface = Color.white
    static let cardBorder = Color(red: 0.906, green: 0.914, blue: 0.933)
    static let textSecondary = Color(red: 0.420, green: 0.447, blue: 0.502)
    static let textTertiary = Color(red: 0.612, green: 0.639, blue: 0.686)

    /// A small fixed palette used to color-code devices consistently across every
    /// screen (dashboard chips, child-detail rows, analysis charts). Kept separate
    /// from the status colors above.
    private static let devicePalette: [Color] = [
        Color(red: 0.298, green: 0.494, blue: 0.953), // blue
        Color(red: 0.545, green: 0.361, blue: 0.965), // purple
        Color(red: 0.941, green: 0.588, blue: 0.243), // orange
        Color(red: 0.925, green: 0.416, blue: 0.620), // pink
        Color(red: 0.243, green: 0.663, blue: 0.667), // teal
        primary
    ]

    static func statusColor(for status: DailyLimitStatus) -> Color {
        switch status {
        case .normal: success
        case .nearLimit, .reached: warning
        case .exceeded: danger
        }
    }

    static func statusTintColor(for status: DailyLimitStatus) -> Color {
        switch status {
        case .normal: successTint
        case .nearLimit, .reached: warningTint
        case .exceeded: dangerTint
        }
    }

    /// A stable color for a given device, so the same device always renders in the
    /// same color everywhere it appears in the app.
    static func color(forDeviceID id: UUID) -> Color {
        devicePalette[abs(id.hashValue) % devicePalette.count]
    }
}
