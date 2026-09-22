import SwiftUI

/// A small pill showing one device's usage total, color-coded per `AppTheme.color(forDeviceID:)`.
/// Used on the dashboard and child-detail screens so a parent can see the device
/// breakdown without opening a separate screen.
struct DeviceUsageChip: View {
    let name: String
    let minutes: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(name) · \(UsageAggregator.format(minutes: minutes))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.background, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        DeviceUsageChip(name: "Phone", minutes: 45, color: AppTheme.color(forDeviceID: UUID()))
        DeviceUsageChip(name: "Chromebook", minutes: 30, color: AppTheme.color(forDeviceID: UUID()))
    }
    .padding()
}
