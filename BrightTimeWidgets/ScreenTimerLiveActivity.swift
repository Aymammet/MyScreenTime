import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for a running screen timer.
struct ScreenTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScreenTimerAttributes.self) { context in
            TimerLockScreenView(context: context)
                .activityBackgroundTint(WidgetPalette.background)
                .activitySystemActionForegroundColor(WidgetPalette.teal)
        } dynamicIsland: { context in
            let color = Color(widgetHex: context.attributes.colorHex)
            let range = context.state.startedAt...max(context.state.endsAt, context.state.startedAt)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        InitialBadge(initial: context.attributes.initial, color: color, size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.attributes.childName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(context.attributes.deviceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(timerInterval: range, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(color)
                        Text("Ends at \(context.state.endsAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                InitialBadge(initial: context.attributes.initial, color: color, size: 22)
            } compactTrailing: {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .frame(maxWidth: 46)
            } minimal: {
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Text(context.attributes.initial)
                        .font(.caption2.weight(.bold))
                }
                .progressViewStyle(.circular)
                .tint(color)
            }
            .keylineTint(color)
        }
    }
}

private struct TimerLockScreenView: View {
    let context: ActivityViewContext<ScreenTimerAttributes>

    var body: some View {
        let color = Color(widgetHex: context.attributes.colorHex)
        let range = context.state.startedAt...max(context.state.endsAt, context.state.startedAt)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                InitialBadge(initial: context.attributes.initial, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.childName) · \(context.attributes.deviceName)")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.deep)
                        .lineLimit(1)
                    Text(context.isStale ? "Time's up" : "Screen time left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.secondary)
                }
                Spacer(minLength: 8)
                Text(timerInterval: range, countsDown: true)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.deep)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            ProgressView(timerInterval: range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(color)
            HStack {
                Label("BrightTime", systemImage: "sun.max.fill")
                    .foregroundStyle(WidgetPalette.tealBright)
                Spacer()
                Text("Ends at \(context.state.endsAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(WidgetPalette.secondary)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
    }
}

private struct InitialBadge: View {
    let initial: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}
