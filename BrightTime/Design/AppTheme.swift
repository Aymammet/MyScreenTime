import SwiftUI

enum AppTheme {
    // BrightTime's core identity: a calm periwinkle that feels optimistic and
    // analytical without the heavy dark-green appearance of the first design.
    static let primary = Color(red: 0.302, green: 0.431, blue: 0.965)
    static let primaryDeep = Color(red: 0.157, green: 0.157, blue: 0.427)
    static let primaryTint = Color(red: 0.927, green: 0.933, blue: 1.000)
    static let lavender = Color(red: 0.545, green: 0.494, blue: 0.961)
    static let rose = Color(red: 0.925, green: 0.365, blue: 0.624)

    // Status colors. These intentionally never overlap the device palette below,
    // so a color can only ever mean "limit status" or "which device" — never both.
    static let success = Color(red: 0.302, green: 0.431, blue: 0.965)
    static let successTint = Color(red: 0.927, green: 0.933, blue: 1.000)
    static let warning = Color(red: 0.871, green: 0.604, blue: 0.235)
    static let warningTint = Color(red: 0.984, green: 0.941, blue: 0.875)
    static let danger = Color(red: 0.882, green: 0.357, blue: 0.322)
    static let dangerTint = Color(red: 0.984, green: 0.906, blue: 0.898)

    // Neutral surfaces used for the card-based layout.
    static let background = Color(red: 0.965, green: 0.969, blue: 0.992)
    static let surface = Color.white
    static let cardBorder = Color(red: 0.887, green: 0.891, blue: 0.961)
    static let textSecondary = Color(red: 0.376, green: 0.388, blue: 0.525)
    static let textTertiary = Color(red: 0.573, green: 0.584, blue: 0.690)

    /// A small fixed palette used to color-code devices consistently across every
    /// screen (dashboard chips, child-detail rows, analysis charts). Kept separate
    /// from the status colors above.
    private static let devicePalette: [Color] = [
        Color(red: 0.298, green: 0.494, blue: 0.953), // blue
        Color(red: 0.545, green: 0.361, blue: 0.965), // purple
        Color(red: 0.941, green: 0.588, blue: 0.243), // orange
        Color(red: 0.925, green: 0.416, blue: 0.620), // pink
        Color(red: 0.376, green: 0.655, blue: 0.949), // light blue
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
