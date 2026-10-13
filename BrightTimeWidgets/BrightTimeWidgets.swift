import SwiftUI
import UIKit
import WidgetKit

@main
struct BrightTimeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FamilyWidget()
        ScreenTimerLiveActivity()
    }
}

// MARK: - Palette (mirrors the app's teal theme)

enum WidgetPalette {
    static let teal = Color(widgetHex: 0x2F8F8A)
    static let tealBright = adaptive(light: 0x2F8F8A, dark: 0x3FB0A9)
    static let deep = adaptive(light: 0x173F3C, dark: 0xF2F2EF)
    static let secondary = adaptive(light: 0x677976, dark: 0x9AA3A1)
    static let background = adaptive(light: 0xFAF5EC, dark: 0x0B0F0E)
    static let track = adaptive(light: 0xE6DFD1, dark: 0x1F2726)
    static let danger = adaptive(light: 0xB4402F, dark: 0xEE7562)
    static let warning = adaptive(light: 0xA86A0E, dark: 0xF0AE45)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Timeline

struct FamilyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var children: [WidgetSnapshot.Child] { snapshot.children }

    /// The child whose timer ends soonest, if any timer is running.
    var nextTimerChild: WidgetSnapshot.Child? {
        children
            .filter { $0.runningTimer(at: date) != nil }
            .min { ($0.timer?.endsAt ?? .distantFuture) < ($1.timer?.endsAt ?? .distantFuture) }
    }

    var familyLimit: Int { children.reduce(0) { $0 + $1.limitMinutes } }

    var familyUsed: Int {
        children.reduce(0) { $0 + $1.usedMinutes(at: date, dayEndsAt: snapshot.dayEndsAt) }
    }

    var familyLeft: Int { familyLimit - familyUsed }

    func left(for child: WidgetSnapshot.Child) -> Int {
        child.leftMinutes(at: date, dayEndsAt: snapshot.dayEndsAt)
    }
}

struct FamilyProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyEntry {
        FamilyEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FamilyEntry) -> Void) {
        let stored = WidgetSnapshot.load()
        let snapshot = context.isPreview && (stored?.children.isEmpty ?? true) ? .preview : (stored ?? .empty)
        completion(FamilyEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FamilyEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .empty
        let now = Date.now
        var dates: Set<Date> = [now]

        // While a timer runs, refresh every 5 minutes so "time left" keeps up,
        // and once more right when it ends.
        for child in snapshot.children {
            guard let timer = child.timer, timer.endsAt > now else { continue }
            var next = now.addingTimeInterval(300)
            while next < timer.endsAt {
                dates.insert(next)
                next = next.addingTimeInterval(300)
            }
            dates.insert(timer.endsAt)
        }
        if snapshot.dayEndsAt > now {
            dates.insert(snapshot.dayEndsAt)
        }

        let entries = dates.sorted().prefix(80).map { FamilyEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        generatedAt: .now,
        dayEndsAt: .now.addingTimeInterval(36_000),
        children: [
            .init(
                id: UUID(), name: "Emir", colorHex: 0x3E76EC, usedMinutes: 55, limitMinutes: 120, bankMinutes: 30,
                timer: .init(deviceName: "TV", startedAt: .now.addingTimeInterval(-600), endsAt: .now.addingTimeInterval(1_200))
            ),
            .init(id: UUID(), name: "Aylin", colorHex: 0xE25890, usedMinutes: 80, limitMinutes: 90, bankMinutes: 0, timer: nil),
        ]
    )
}

// MARK: - Family widget

struct FamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: FamilyProvider()) { entry in
            FamilyWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("Screen time")
        .description("Time left today and running timers for each kid.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct FamilyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FamilyEntry

    var body: some View {
        if entry.children.isEmpty {
            emptyView
        } else {
            switch family {
            case .systemMedium: mediumView
            case .accessoryCircular: circularView
            case .accessoryRectangular: rectangularView
            case .accessoryInline: inlineView
            default: smallView
            }
        }
    }

    // MARK: Home Screen

    @ViewBuilder
    private var smallView: some View {
        if let child = entry.nextTimerChild, let timer = child.runningTimer(at: entry.date) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AvatarDot(child: child, size: 22)
                    Text(child.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WidgetPalette.deep)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "timer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetPalette.tealBright)
                }
                Spacer(minLength: 0)
                Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.deep)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(timer.deviceName) time left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                ProgressView(timerInterval: timer.startedAt...timer.endsAt, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(child.color)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Family today", systemImage: "sun.max.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetPalette.tealBright)
                Text(WidgetTime.compact(entry.familyLeft))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.familyLeft < 0 ? WidgetPalette.danger : WidgetPalette.deep)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.familyLeft < 0 ? "over today" : "left today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer(minLength: 4)
                ForEach(entry.children.prefix(3)) { child in
                    HStack(spacing: 6) {
                        Circle().fill(child.color).frame(width: 7, height: 7)
                        Text(child.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetPalette.deep)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        leftText(entry.left(for: child))
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("BrightTime", systemImage: "sun.max.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetPalette.tealBright)
                Spacer()
                Text(entry.familyLeft < 0
                     ? "Family \(WidgetTime.compact(entry.familyLeft)) over"
                     : "Family \(WidgetTime.compact(entry.familyLeft)) left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
            }

            ForEach(entry.children.prefix(3)) { child in
                childRow(child)
            }
            Spacer(minLength: 0)
        }
    }

    private func childRow(_ child: WidgetSnapshot.Child) -> some View {
        let used = child.usedMinutes(at: entry.date, dayEndsAt: entry.snapshot.dayEndsAt)
        let progress = child.limitMinutes > 0 ? min(Double(used) / Double(child.limitMinutes), 1) : 0
        let left = entry.left(for: child)

        return HStack(spacing: 10) {
            AvatarDot(child: child, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(child.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WidgetPalette.deep)
                        .lineLimit(1)
                    if child.bankMinutes > 0 {
                        Text("+\(WidgetTime.compact(child.bankMinutes)) banked")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let timer = child.runningTimer(at: entry.date) {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                            Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                                .monospacedDigit()
                                .frame(maxWidth: 52, alignment: .trailing)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetPalette.tealBright)
                    } else {
                        leftText(left)
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                Capsule()
                    .fill(WidgetPalette.track)
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(left < 0 ? WidgetPalette.danger : child.color)
                                .frame(width: max(geometry.size.width * progress, 6))
                        }
                    }
            }
        }
    }

    private func leftText(_ minutes: Int) -> some View {
        Text(minutes < 0 ? "\(WidgetTime.compact(minutes)) over" : "\(WidgetTime.compact(minutes)) left")
            .foregroundStyle(minutes < 0 ? WidgetPalette.danger : (minutes <= 10 ? WidgetPalette.warning : WidgetPalette.deep))
            .lineLimit(1)
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var circularView: some View {
        if let child = entry.nextTimerChild, let timer = child.runningTimer(at: entry.date) {
            ProgressView(timerInterval: timer.startedAt...timer.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(child.initial)
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            let limit = max(entry.familyLimit, 1)
            Gauge(value: Double(min(max(entry.familyUsed, 0), limit)), in: 0...Double(limit)) {
                Image(systemName: "sun.max.fill")
            } currentValueLabel: {
                Text(WidgetTime.compact(max(entry.familyLeft, 0)))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if let child = entry.nextTimerChild, let timer = child.runningTimer(at: entry.date) {
            VStack(alignment: .leading, spacing: 1) {
                Label("\(child.name) · \(timer.deviceName)", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .widgetAccentable()
                Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("\(WidgetTime.compact(max(entry.left(for: child), 0))) left today")
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label("BrightTime", systemImage: "sun.max.fill")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                ForEach(entry.children.prefix(2)) { child in
                    let left = entry.left(for: child)
                    Text("\(child.name): \(left < 0 ? "\(WidgetTime.compact(left)) over" : "\(WidgetTime.compact(left)) left")")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        if let child = entry.nextTimerChild, let timer = child.runningTimer(at: entry.date) {
            Label {
                Text("\(child.name) ") + Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
            } icon: {
                Image(systemName: "timer")
            }
        } else {
            Label(
                entry.familyLeft < 0
                    ? "Family \(WidgetTime.compact(entry.familyLeft)) over"
                    : "Family \(WidgetTime.compact(entry.familyLeft)) left",
                systemImage: "sun.max.fill"
            )
        }
    }

    // MARK: Empty

    @ViewBuilder
    private var emptyView: some View {
        switch family {
        case .accessoryInline:
            Label("Add a kid in BrightTime", systemImage: "sun.max.fill")
        case .accessoryCircular:
            Image(systemName: "sun.max.fill")
                .font(.title2)
        case .accessoryRectangular:
            Text("Add a kid in BrightTime to see their time here.")
                .font(.caption)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(WidgetPalette.tealBright)
                Spacer(minLength: 0)
                Text("Add a kid in BrightTime to see their screen time here.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.deep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AvatarDot: View {
    let child: WidgetSnapshot.Child
    let size: CGFloat

    var body: some View {
        Text(child.initial)
            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(child.color, in: Circle())
    }
}

#Preview(as: .systemMedium) {
    FamilyWidget()
} timeline: {
    FamilyEntry(date: .now, snapshot: .preview)
}
