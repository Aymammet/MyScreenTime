import SwiftUI

/// A circular progress ring used to show a child's daily screen-time status at a
/// glance. Replaces the flat linear progress bars used elsewhere in the app on the
/// dashboard and child-detail screens, where status needs to be readable instantly.
struct RingProgressView: View {
    private let progress: Double
    private let color: Color
    private let trackColor: Color
    private let size: CGFloat
    private let lineWidth: CGFloat

    init(
        progress: Double,
        color: Color,
        trackColor: Color = AppTheme.cardBorder,
        size: CGFloat = 52,
        lineWidth: CGFloat = 5
    ) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.trackColor = trackColor
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(progress, 0.0001))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: color)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        RingProgressView(progress: 0.63, color: AppTheme.success)
        RingProgressView(progress: 0.96, color: AppTheme.warning)
        RingProgressView(progress: 1, color: AppTheme.danger)
    }
    .padding()
}
