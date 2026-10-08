import SwiftUI

// Shared building blocks for the teal redesign, so every tab uses the same cards,
// chips, rings and steppers instead of re-styling them screen by screen.

// MARK: - Sun ring

/// BrightTime's signature shape: a progress ring with eight short "sun" rays around
/// it, echoing the app icon. Fills in from zero when it appears, then eases to new
/// values. Honors Reduce Motion.
struct SunRingView<Center: View>: View {
    private let progress: Double
    private let color: Color
    private let trackColor: Color
    private let rayColor: Color?
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownProgress: Double = 0

    init(
        progress: Double,
        color: Color,
        trackColor: Color = AppTheme.surfaceMuted,
        rayColor: Color? = nil,
        size: CGFloat = 120,
        lineWidth: CGFloat = 10,
        @ViewBuilder center: () -> Center
    ) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.trackColor = trackColor
        self.rayColor = rayColor
        self.size = size
        self.lineWidth = lineWidth
        self.center = center()
    }

    var body: some View {
        let rayLength = size * 0.075
        let rayWidth = max(size * 0.03, 2)
        let gap = size * 0.06
        let ringDiameter = size - 2 * (rayLength + gap) - lineWidth

        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(rayColor ?? color.opacity(0.45))
                    .frame(width: rayWidth, height: rayLength)
                    .offset(y: -(size / 2 - rayLength / 2))
                    .rotationEffect(.degrees(Double(index) * 45))
            }

            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
                .frame(width: ringDiameter, height: ringDiameter)

            Circle()
                .trim(from: 0, to: max(shownProgress, 0.001))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)

            center
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: color)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) {
                shownProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                shownProgress = newValue
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

extension SunRingView where Center == EmptyView {
    init(
        progress: Double,
        color: Color,
        trackColor: Color = AppTheme.surfaceMuted,
        rayColor: Color? = nil,
        size: CGFloat = 120,
        lineWidth: CGFloat = 10
    ) {
        self.init(
            progress: progress,
            color: color,
            trackColor: trackColor,
            rayColor: rayColor,
            size: size,
            lineWidth: lineWidth
        ) {
            EmptyView()
        }
    }
}

// MARK: - Cards

private struct BrightCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.surface,
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    /// The standard white (dark: deep-teal) rounded card used on every tab.
    func brightCard(padding: CGFloat = 16) -> some View {
        modifier(BrightCardModifier(padding: padding))
    }
}

/// Bold card title with an optional quiet detail on the right.
struct CardTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryDeep)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Section label that sits between cards ("Your children").
struct SectionLabel<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.primaryDeep)
            Spacer()
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Chips & tiles

struct BrightChip: View {
    let text: String
    var systemImage: String?
    var foreground: Color = AppTheme.primary
    var background: Color = AppTheme.primaryTint

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
    }

    /// A chip colored by limit status. Always carries words, never color alone.
    static func status(_ text: String, _ status: DailyLimitStatus) -> BrightChip {
        BrightChip(
            text: text,
            foreground: AppTheme.statusTextColor(for: status),
            background: AppTheme.statusTintColor(for: status)
        )
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var detail: String?
    var detailColor: Color = AppTheme.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.primaryDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slim horizontal bar, e.g. a child's share of today's limit.
struct LimitBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.surfaceMuted)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.5), value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Period stepper

/// "‹ Sep 29 – Oct 5 ›" control for moving between weeks or months.
struct PeriodStepper: View {
    let title: String
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous period")

            Spacer(minLength: 0)

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryDeep)
                .contentTransition(.numericText())
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
            .accessibilityLabel("Next period")
        }
        .buttonStyle(.plain)
        .font(.body.weight(.bold))
        .foregroundStyle(AppTheme.primary)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

// MARK: - Formatting

enum TimeText {
    /// "1h 40m", "52m", "3h" — the compact form used across the redesigned tabs.
    static func compact(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    /// "+12%" / "−8%" style comparison text, or nil when there's nothing to compare.
    static func change(_ percent: Int?) -> String? {
        guard let percent else { return nil }
        if percent == 0 { return "Same as before" }
        return percent > 0 ? "↑ \(percent)% vs last" : "↓ \(abs(percent))% vs last"
    }

    /// Lower usage is good news (teal), higher is a heads-up (coral).
    static func changeColor(_ percent: Int?) -> Color {
        guard let percent, percent != 0 else { return AppTheme.textSecondary }
        return percent > 0 ? AppTheme.dangerText : AppTheme.primary
    }
}
