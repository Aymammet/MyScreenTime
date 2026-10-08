import SwiftUI
import UIKit

enum AppTheme {
    // MARK: - Brand
    // Taken straight from the sun-clock app icon: teal for "on track", a deep teal
    // for text, warm cream surfaces. Brighter than the first dark-green design so
    // the app reads calm and optimistic rather than heavy.

    static let primary = adaptive(light: 0x2F8F8A, dark: 0x3AA39D)
    static let primaryDeep = adaptive(light: 0x173F3C, dark: 0xF3EEE4)
    static let primaryTint = adaptive(light: 0xE2F1EE, dark: 0x1D3F3C)
    static let primarySoft = adaptive(light: 0xA9D6D0, dark: 0x2C6662)
    static let cream = Color(hex: 0xFBF3E4)

    /// Hero-card gradient (Home "Family today" card, selected tab pill).
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x3A9D97), Color(hex: 0x2F8F8A), Color(hex: 0x1F6A66)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Older names kept so screens that still reference them pick up the new palette.
    static let lavender = primarySoft
    static let rose = Color(hex: 0xC2568F)

    // MARK: - Status
    // Teal = on track, amber = close to the limit, coral = over. These never appear
    // in the device palette below, so a color only ever means one thing.

    static let success = primary
    static let successTint = primaryTint
    static let warning = adaptive(light: 0xE09A2D, dark: 0xF0AE45)
    static let warningTint = adaptive(light: 0xFBEFD9, dark: 0x3A2E17)
    /// Amber is too light for small text on cream; use this for amber labels.
    static let warningText = adaptive(light: 0xA86A0E, dark: 0xF0AE45)
    static let danger = adaptive(light: 0xDD5E4B, dark: 0xEE7562)
    static let dangerTint = adaptive(light: 0xFBE4DF, dark: 0x3D221E)
    static let dangerText = adaptive(light: 0xB4402F, dark: 0xEE7562)

    // MARK: - Surfaces & text

    static let background = adaptive(light: 0xFAF5EC, dark: 0x0F2523)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x17312F)
    static let surfaceMuted = adaptive(light: 0xF1ECE2, dark: 0x1E3A37)
    static let cardBorder = adaptive(light: 0xEEE7DA, dark: 0x23413E)
    static let textSecondary = adaptive(light: 0x677976, dark: 0xA3B5B1)
    static let textTertiary = adaptive(light: 0x9AA8A5, dark: 0x70827E)

    // MARK: - Shape & motion

    static let cardRadius: CGFloat = 20

    /// The one spring used for tab switches, period steppers and expanding cards.
    static var spring: Animation { .spring(response: 0.35, dampingFraction: 0.85) }

    /// Springs everywhere, or a short fade when the person has Reduce Motion on.
    static func motion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : spring
    }

    // MARK: - Devices

    /// A fixed palette used to color-code devices across every screen. Deliberately
    /// excludes teal, amber and coral (the status colors).
    private static let devicePalette: [Color] = [
        Color(hex: 0x3B7DD8), // ocean
        Color(hex: 0x7B61D1), // violet
        Color(hex: 0xC2568F), // berry
        Color(hex: 0x5E7182), // slate
        Color(hex: 0x2F5D9E)  // denim
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

    /// Readable text color for a status label sitting on its tint.
    static func statusTextColor(for status: DailyLimitStatus) -> Color {
        switch status {
        case .normal: primary
        case .nearLimit, .reached: warningText
        case .exceeded: dangerText
        }
    }

    /// A stable color for a given device. Uses the UUID's bytes rather than
    /// `hashValue`, which Swift re-seeds on every launch.
    static func color(forDeviceID id: UUID) -> Color {
        devicePalette[stableIndex(for: id, count: devicePalette.count)]
    }

    static func stableIndex(for id: UUID, count: Int) -> Int {
        id.stableIndex(count: count)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension UUID {
    /// An index in `0..<count` that stays the same across launches (unlike
    /// `hashValue`, which Swift re-seeds every run).
    func stableIndex(count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = withUnsafeBytes(of: uuid) { bytes in
            bytes.reduce(0) { $0 &+ Int($1) }
        }
        return sum % count
    }
}
