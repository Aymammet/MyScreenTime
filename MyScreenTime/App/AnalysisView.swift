import Charts
import SwiftUI

enum AnalysisDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case devices = "Devices"
    case children = "Children"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .weekly: "chart.bar.fill"
        case .monthly: "calendar"
        case .devices: "display.2"
        case .children: "person.2.fill"
        }
    }
}

struct AnalysisView: View {
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]
    let destination: AnalysisDestination

    @State private var period: AnalysisPeriod = .week

    private var weeklyAnalysis: PeriodAnalysis {
        AnalysisCalculator.analyze(
            period: .week,
            now: .now,
            childIDs: Set(children.filter(\.isActive).map(\.id)),
            sessions: sessions,
            devices: devices
        )
    }

    var body: some View {
        selectedAnalysis
        .tint(AppTheme.primary)
        .navigationTitle(destination.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var selectedAnalysis: some View {
        switch destination {
        case .home: weeklyAnalysisTab
        case .weekly: weeklyAnalysisTab
        case .monthly: monthlyAnalysisTab
        case .devices: deviceAnalysisTab
        case .children: childAnalysisTab
        }
    }

    private var weeklyAnalysisTab: some View {
        List {
            Section("This week") {
                LabeledContent("Total", value: UsageAggregator.format(minutes: weeklyAnalysis.currentMinutes))
                LabeledContent("Daily average", value: UsageAggregator.format(minutes: weeklyAnalysis.dailyAverageMinutes))
                LabeledContent("Previous week", value: UsageAggregator.format(minutes: weeklyAnalysis.previousMinutes))
                comparisonRow(for: weeklyAnalysis)
            }

            Section("Usage trend") {
                if weeklyAnalysis.dailyPoints.allSatisfy({ $0.minutes == 0 }) {
                    emptyChart("No usage recorded this week yet.")
                } else {
                    Chart(weeklyAnalysis.dailyPoints) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes", point.minutes)
                        )
                        .foregroundStyle(AppTheme.primary.gradient)
                        .cornerRadius(4)
                    }
                    .chartYAxisLabel("Minutes")
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) {
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .frame(height: 220)
                    .accessibilityIdentifier("usage-trend-chart")
                }
            }

            Section("Device breakdown") {
                if weeklyAnalysis.devicePoints.isEmpty {
                    emptyChart("Device usage will appear after a session is recorded.")
                } else {
                    Chart(weeklyAnalysis.devicePoints) { point in
                        BarMark(
                            x: .value("Minutes", point.minutes),
                            y: .value("Device", point.name)
                        )
                        .foregroundStyle(by: .value("Device", point.name))
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(height: max(CGFloat(weeklyAnalysis.devicePoints.count) * 48, 150))
                    .accessibilityIdentifier("device-breakdown-chart")
                }
            }
            DailyInsightsSection()
        }
    }

    private var childAnalysisTab: some View {
        List {
            periodPicker

            if activeChildren.isEmpty {
                ContentUnavailableView(
                    "No children to analyze",
                    systemImage: "person.2.slash",
                    description: Text("Add a child and record usage to see individual analysis.")
                )
            } else {
                ForEach(activeChildren) { child in
                    Section {
                        let childAnalysis = analysis(for: child)
                        analysisCard(
                            title: "All screen time",
                            icon: "person.crop.circle.fill",
                            analysis: childAnalysis
                        )

                        let childDevices = devicesAvailable(to: child)
                        if childDevices.isEmpty {
                            Text("No devices available for this child.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(childDevices) { device in
                                childDeviceAnalysisRow(device, child: child)
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            ChildAvatarView(child: child, size: 28)
                            Text(child.name)
                        }
                    }
                }
            }
            DailyInsightsSection()
        }
    }

    private var deviceAnalysisTab: some View {
        List {
            periodPicker

            Section("Device analysis") {
                if activeDevices.isEmpty {
                    ContentUnavailableView(
                        "No devices to analyze",
                        systemImage: "display.2",
                        description: Text("Add a device and record usage to see device analysis.")
                    )
                } else {
                    ForEach(activeDevices) { device in
                        let deviceAnalysis = analysis(for: device)
                        analysisCard(
                            title: device.name,
                            subtitle: device.isShared ? "Shared household" : device.child?.name,
                            icon: device.kind.systemImage,
                            analysis: deviceAnalysis
                        )
                    }
                }
            }
            DailyInsightsSection()
        }
    }

    private var monthlyAnalysisTab: some View {
        let monthly = AnalysisCalculator.analyze(
            period: .month,
            now: .now,
            childIDs: Set(activeChildren.map(\.id)),
            sessions: sessions,
            devices: devices
        )

        return List {
            Section("This month") {
                LabeledContent("Total", value: UsageAggregator.format(minutes: monthly.currentMinutes))
                LabeledContent("Daily average", value: UsageAggregator.format(minutes: monthly.dailyAverageMinutes))
                LabeledContent("Previous month", value: UsageAggregator.format(minutes: monthly.previousMinutes))
                comparisonRow(for: monthly)
            }

            Section("Daily usage") {
                if monthly.dailyPoints.allSatisfy({ $0.minutes == 0 }) {
                    emptyChart("No usage recorded this month yet.")
                } else {
                    Chart(monthly.dailyPoints) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes", point.minutes)
                        )
                        .foregroundStyle(AppTheme.primary)

                        AreaMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes", point.minutes)
                        )
                        .foregroundStyle(AppTheme.primary.opacity(0.15))
                    }
                    .chartYAxisLabel("Minutes")
                    .frame(height: 220)
                }
            }
            DailyInsightsSection()
        }
    }

    private var periodPicker: some View {
        Section {
            Picker("Analysis period", selection: $period) {
                ForEach(AnalysisPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var activeChildren: [ChildProfile] {
        children.filter(\.isActive)
    }

    private var activeDevices: [Device] {
        devices.filter { $0.isActive && ($0.isShared || $0.child?.isActive == true) }
    }

    private func analysis(for child: ChildProfile) -> PeriodAnalysis {
        AnalysisCalculator.analyze(
            period: period,
            now: .now,
            childIDs: [child.id],
            sessions: sessions,
            devices: devices.filter { $0.isAvailable(to: child.id) }
        )
    }

    private func analysis(for device: Device) -> PeriodAnalysis {
        let childIDs = device.isShared
            ? Set(activeChildren.map(\.id))
            : Set(device.child.map { [$0.id] } ?? [])

        return AnalysisCalculator.analyze(
            period: period,
            now: .now,
            childIDs: childIDs,
            sessions: sessions.filter { $0.device?.id == device.id },
            devices: [device]
        )
    }

    private func analysis(for device: Device, child: ChildProfile) -> PeriodAnalysis {
        AnalysisCalculator.analyze(
            period: period,
            now: .now,
            childIDs: [child.id],
            sessions: sessions.filter {
                $0.child?.id == child.id && $0.device?.id == device.id
            },
            devices: [device]
        )
    }

    private func devicesAvailable(to child: ChildProfile) -> [Device] {
        devices
            .filter { $0.isActive && $0.isAvailable(to: child.id) }
            .sorted { lhs, rhs in
                if lhs.isShared != rhs.isShared { return !lhs.isShared }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func childDeviceAnalysisRow(_ device: Device, child: ChildProfile) -> some View {
        let deviceAnalysis = analysis(for: device, child: child)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.systemImage)
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                    Text(device.isShared ? "Shared household device" : device.kind.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(UsageAggregator.format(minutes: deviceAnalysis.currentMinutes))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }

            HStack {
                Text("\(UsageAggregator.format(minutes: deviceAnalysis.dailyAverageMinutes)) daily average")
                    .foregroundStyle(.secondary)
                Spacer()
                compactComparison(for: deviceAnalysis)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("child-device-analysis-\(child.id.uuidString)-\(device.id.uuidString)")
    }

    private func analysisCard(
        title: String,
        subtitle: String? = nil,
        icon: String,
        analysis: PeriodAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(UsageAggregator.format(minutes: analysis.currentMinutes))
                    .font(.headline)
            }

            HStack {
                Label(
                    "\(UsageAggregator.format(minutes: analysis.dailyAverageMinutes)) daily average",
                    systemImage: "clock"
                )
                Spacer()
                compactComparison(for: analysis)
            }
            .font(.caption)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func comparisonRow(for analysis: PeriodAnalysis) -> some View {
        if let change = analysis.changePercent {
            let isHigher = change > 0
            LabeledContent("Change") {
                Label("\(abs(change))% \(isHigher ? "above" : change < 0 ? "below" : "same as")", systemImage: isHigher ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "equal")
                    .foregroundStyle(isHigher ? AppTheme.warning : change < 0 ? AppTheme.success : .secondary)
            }
        } else {
            LabeledContent("Change", value: "No previous usage")
        }
    }

    @ViewBuilder
    private func compactComparison(for analysis: PeriodAnalysis) -> some View {
        if let change = analysis.changePercent {
            let isHigher = change > 0
            Label(
                change == 0 ? "No change" : "\(abs(change))% \(isHigher ? "higher" : "lower")",
                systemImage: change == 0 ? "equal" : isHigher ? "arrow.up.right" : "arrow.down.right"
            )
            .foregroundStyle(isHigher ? AppTheme.warning : change < 0 ? AppTheme.success : .secondary)
        } else {
            Text("No comparison yet")
                .foregroundStyle(.secondary)
        }
    }

    private func emptyChart(_ message: String) -> some View {
        ContentUnavailableView("Not enough data", systemImage: "chart.bar.xaxis", description: Text(message))
    }
}

private struct DailyInsightsSection: View {
    private enum LoadState {
        case loading
        case ready([DailyInsight])
        case unavailable
    }

    @State private var state: LoadState = .loading

    var body: some View {
        Section {
            switch state {
            case .loading:
                ProgressView("Loading insights…")
                    .accessibilityIdentifier("daily-insights-loading")
            case .ready(let items):
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No verified stories yet", systemImage: "newspaper")
                            .font(.headline)
                        Text("Screen-time statistics, news, and expert guidance will appear here once a reviewed content source is connected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("daily-insights-empty")
                } else {
                    ForEach(items) { insight in
                        insightCard(insight)
                    }
                }
            case .unavailable:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insights unavailable", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("The content could not be loaded. Your usage records are unaffected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { load() }
                }
                .accessibilityIdentifier("daily-insights-unavailable")
            }
        } header: {
            Text("Daily insights")
        } footer: {
            Text("News and statistics describe their stated region and publication date; they are not measurements of your children.")
        }
        .task { load() }
    }

    private func load() {
        do {
            state = .ready(try DailyInsightsCatalog.load())
        } catch {
            state = .unavailable
        }
    }

    private func insightCard(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(insight.kind.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
            Text(insight.title)
                .font(.headline)
            Text(insight.summary)
                .font(.subheadline)
            Text("\(insight.sourceName) · \(insight.region)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Published \(insight.publishedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if insight.needsReview(at: .now) {
                Label("Older content — check the source for updates", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }
            Link(destination: insight.sourceURL) {
                Label("Read source", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityHint("Opens the original article in your browser")
        }
        .padding(.vertical, 8)
    }
}
