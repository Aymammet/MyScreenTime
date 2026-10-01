// xcode: set sdk=iOS

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

/// The time range shown within the combined Analytics tab. Weekly and Monthly used
/// to be separate bottom-nav tabs; they're now one tab with this in-page switch so
/// the nav bar stays simple.
enum AnalyticsScope: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }
}

struct AnalysisView: View {
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]
    let destination: AnalysisDestination

    @State private var period: AnalysisPeriod = .week
    @State private var isAddingDevice = false

    private var weeklyAnalysis: PeriodAnalysis {
        AnalysisCalculator.analyze(
            period: .week,
            now: .now,
            childIDs: Set(children.filter(\.isActive).map(\.id)),
            sessions: sessions,
            devices: devices
        )
    }

    private var monthlyAnalysis: PeriodAnalysis {
        AnalysisCalculator.analyze(
            period: .month,
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
        .sheet(isPresented: $isAddingDevice) {
            DeviceFormView(children: activeChildren)
        }
    }

    @ViewBuilder
    private var selectedAnalysis: some View {
        switch destination {
        case .home: analysisTab(scope: .weekly)
        case .weekly: analysisTab(scope: .weekly)
        case .monthly: analysisTab(scope: .monthly)
        case .devices: deviceAnalysisTab
        case .children: childAnalysisTab
        }
    }

    private func analysisTab(scope: AnalyticsScope) -> some View {
        List {
            switch scope {
            case .weekly:
                Section {
                    statTilesRow(for: weeklyAnalysis, totalLabel: "Week total")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    trendCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    deviceBreakdownCard(for: weeklyAnalysis)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            case .monthly:
                Section {
                    statTilesRow(for: monthlyAnalysis, totalLabel: "Month total")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    monthlyTrendCard(monthlyAnalysis)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            DailyInsightsSection()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .contentMargins(.bottom, 100, for: .scrollContent)
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
                        VStack(spacing: 12) {
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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(childDevices) { device in
                                        childDeviceAnalysisRow(device, child: child)
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    } header: {
                        HStack(spacing: 8) {
                            ChildAvatarView(child: child, size: 28)
                            Text(child.name)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            DailyInsightsSection()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .contentMargins(.bottom, 100, for: .scrollContent)
    }

    private var deviceAnalysisTab: some View {
        List {
            Section {
                Button {
                    isAddingDevice = true
                } label: {
                    Label("Add new device", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("devices-add-device-button")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)

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
                        deviceAnalysisCard(device)
                        .padding(18)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            DailyInsightsSection()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .contentMargins(.bottom, 100, for: .scrollContent)
    }

    // MARK: - Cards

    private func statTilesRow(for analysis: PeriodAnalysis, totalLabel: String) -> some View {
        HStack(spacing: 10) {
            statTile(icon: "clock", value: UsageAggregator.format(minutes: analysis.dailyAverageMinutes), label: "Daily avg")
            statTile(icon: "chart.bar.fill", value: UsageAggregator.format(minutes: analysis.currentMinutes), label: totalLabel)
            changeTile(for: analysis)
        }
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func changeTile(for analysis: PeriodAnalysis) -> some View {
        let change = analysis.changePercent
        let isHigher = (change ?? 0) > 0
        let isLower = (change ?? 0) < 0
        let color: Color = change == nil ? AppTheme.textSecondary : (isHigher ? AppTheme.warning : (isLower ? AppTheme.success : AppTheme.textSecondary))
        let icon = change == nil ? "minus" : (isHigher ? "arrow.up.right" : (isLower ? "arrow.down.right" : "equal"))
        let valueText = change.map { "\(abs($0))%" } ?? "—"
        let label = change == nil ? "No comparison" : (isHigher ? "Above last time" : (isLower ? "Below last time" : "Same as before"))

        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
            Text(valueText)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Usage trend")
                    .font(.subheadline.weight(.bold))
                Spacer()
                changeBadge(for: weeklyAnalysis)
            }

            if weeklyAnalysis.dailyPoints.allSatisfy({ $0.minutes == 0 }) {
                emptyChart("No usage recorded this week yet.")
            } else {
                Chart(weeklyAnalysis.dailyPoints) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(isToday(point.date) ? AppTheme.primary : AppTheme.primary.opacity(0.28))
                    .cornerRadius(4)
                }
                .chartYAxisLabel("Minutes")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) {
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .frame(height: 200)
                .accessibilityIdentifier("usage-trend-chart")
            }
        }
        .padding(18)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func monthlyTrendCard(_ monthly: PeriodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily usage")
                    .font(.subheadline.weight(.bold))
                Spacer()
                changeBadge(for: monthly)
            }

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
                .frame(height: 200)
            }
        }
        .padding(18)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func deviceBreakdownCard(for analysis: PeriodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By device")
                .font(.subheadline.weight(.bold))

            if analysis.devicePoints.isEmpty {
                emptyChart("Device usage will appear after a session is recorded.")
            } else {
                Chart(analysis.devicePoints) { point in
                    BarMark(
                        x: .value("Minutes", point.minutes),
                        y: .value("Device", point.name)
                    )
                    .foregroundStyle(AppTheme.color(forDeviceID: point.deviceID))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(height: max(CGFloat(analysis.devicePoints.count) * 44, 120))
                .accessibilityIdentifier("device-breakdown-chart")
            }
        }
        .padding(18)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func changeBadge(for analysis: PeriodAnalysis) -> some View {
        Group {
            if let change = analysis.changePercent {
                let isHigher = change > 0
                let isLower = change < 0
                let color = isHigher ? AppTheme.warning : (isLower ? AppTheme.success : AppTheme.textSecondary)
                let tint = isHigher ? AppTheme.warningTint : (isLower ? AppTheme.successTint : AppTheme.background)
                Label(
                    "\(abs(change))% \(isHigher ? "above" : isLower ? "below" : "same as") last time",
                    systemImage: isHigher ? "arrow.up.right" : isLower ? "arrow.down.right" : "equal"
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint, in: Capsule())
            }
        }
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
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
        .listRowBackground(Color.clear)
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

    private func deviceAnalysisCard(_ device: Device) -> some View {
        let deviceAnalysis = analysis(for: device)
        let weeklyUsers = weeklyUsageByChild(for: device)

        return VStack(alignment: .leading, spacing: 14) {
            analysisCard(
                title: device.name,
                subtitle: device.isShared ? "Shared household" : "Used by \(device.child?.name ?? "Unassigned")",
                icon: device.kind.systemImage,
                iconColor: AppTheme.color(forDeviceID: device.id),
                analysis: deviceAnalysis
            )

            Divider()

            weeklyUsersBar(weeklyUsers)
        }
        .accessibilityIdentifier("device-analysis-card-\(device.id.uuidString)")
    }

    @ViewBuilder
    private func weeklyUsersBar(_ points: [ChildDeviceUsage]) -> some View {
        if let leader = points.first {
            let totalMinutes = points.reduce(0) { $0 + $1.minutes }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Most used this week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("\(leader.child.name) · \(UsageAggregator.format(minutes: leader.minutes))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primaryDeep)
                }

                GeometryReader { geometry in
                    let spacing = CGFloat(max(points.count - 1, 0)) * 3
                    let usableWidth = max(geometry.size.width - spacing, 1)

                    HStack(spacing: 3) {
                        ForEach(points) { point in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(for: point.child))
                                .frame(width: usableWidth * CGFloat(point.minutes) / CGFloat(totalMinutes))
                        }
                    }
                }
                .frame(height: 10)

                HStack(spacing: 12) {
                    ForEach(points.prefix(3)) { point in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color(for: point.child))
                                .frame(width: 7, height: 7)
                            Text("\(point.child.name) \(UsageAggregator.format(minutes: point.minutes))")
                                .lineLimit(1)
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly usage by child")
            .accessibilityValue("\(leader.child.name) used this device most, for \(UsageAggregator.format(minutes: leader.minutes))")
        } else {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar.xaxis")
                Text("No usage recorded this week")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func weeklyUsageByChild(for device: Device) -> [ChildDeviceUsage] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date.now) else { return [] }

        return activeChildren.compactMap { child in
            let minutes = sessions
                .filter {
                    $0.device?.id == device.id
                        && $0.child?.id == child.id
                        && week.contains($0.startedAt)
                }
                .reduce(0) { $0 + $1.durationMinutes }
            return minutes > 0 ? ChildDeviceUsage(child: child, minutes: minutes) : nil
        }
        .sorted { lhs, rhs in
            if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
            return lhs.child.name.localizedCaseInsensitiveCompare(rhs.child.name) == .orderedAscending
        }
    }

    private func color(for child: ChildProfile) -> Color {
        let palette = [AppTheme.primary, AppTheme.rose, AppTheme.lavender, AppTheme.warning, AppTheme.success]
        let index = activeChildren.firstIndex(where: { $0.id == child.id }) ?? 0
        return palette[index % palette.count]
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
        let deviceColor = AppTheme.color(forDeviceID: device.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(deviceColor)
                    .frame(width: 30, height: 30)
                    .background(deviceColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("child-device-analysis-\(child.id.uuidString)-\(device.id.uuidString)")
    }

    private func analysisCard(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color = AppTheme.primary,
        analysis: PeriodAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
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

private struct ChildDeviceUsage: Identifiable {
    let child: ChildProfile
    let minutes: Int
    var id: UUID { child.id }
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
