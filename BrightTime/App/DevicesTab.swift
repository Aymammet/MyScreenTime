import Charts
import SwiftData
import SwiftUI

/// One clear weekly chart per device. Cards stay full-width so weekday totals,
/// averages and ownership are easy to scan without opening each device.
struct DevicesTab: View {
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]

    @State private var filter: DeviceFilter = .all
    @State private var isAddingDevice = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0

    private enum DeviceFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case shared = "Shared"
        case personal = "Personal"

        var id: String { rawValue }
    }

    private var activeDevices: [Device] {
        devices
            .filter { $0.isActive && ($0.isShared || $0.child?.isActive == true) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredDevices: [Device] {
        switch filter {
        case .all: activeDevices
        case .shared: activeDevices.filter(\.isShared)
        case .personal: activeDevices.filter { !$0.isShared }
        }
    }

    var body: some View {
        let _ = calendarRevision
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Picker("Show", selection: $filter.animation(AppTheme.motion(reduceMotion: reduceMotion))) {
                        ForEach(DeviceFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        isAddingDevice = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.onPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add new device")
                    .accessibilityIdentifier("devices-add-device-button")
                }

                if activeDevices.isEmpty {
                    emptyCard
                } else if filteredDevices.isEmpty {
                    Text(filter == .shared ? "No shared devices yet." : "No personal devices yet.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brightCard()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredDevices) { device in
                            NavigationLink {
                                DeviceDetailView(device: device, children: children, sessions: sessions)
                                    .popsToRootOnTabReselect()
                            } label: {
                                deviceCard(device)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, AppTheme.tabBarContentClearance)
            .scrollTopAnchor()
        }
        .scrollsToTopOnTabReselect()
        .sheet(isPresented: $isAddingDevice) {
            DeviceFormView(children: children)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "ipad.and.iphone")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 64, height: 64)
                .background(AppTheme.primaryTint, in: Circle())
            Text("No devices yet")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            Text("Add the phones, tablets, TVs and consoles your kids use to see time per device.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .brightCard(padding: 24)
    }

    // MARK: - Device card

    private func deviceCard(_ device: Device) -> some View {
        let color = AppTheme.color(forDeviceID: device.id)
        let week = DeviceStats.currentWeek(for: device, sessions: sessions)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: device.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryDeep)
                        .lineLimit(1)
                    Text(device.isShared ? "Shared household device" : "Used by \(device.child?.name ?? "Unassigned")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if device.isShared {
                    BrightChip(text: "Shared")
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            HStack(spacing: 8) {
                weeklyMetric("This week", value: TimeText.compact(week.totalMinutes), color: color)
                weeklyMetric("Daily average", value: TimeText.compact(week.averageMinutes), color: AppTheme.primaryDeep)
            }

            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "Weekly usage", detail: "Daily totals")

                Chart(week.points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(AppCalendar.day.isDateInToday(point.date) ? color : color.opacity(0.62))
                    .cornerRadius(6)
                }
                .chartXScale(domain: week.interval.start...week.interval.end)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(AppTheme.cardBorder)
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text(axisTime(minutes))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("\(device.name) weekly usage")
                .accessibilityValue("\(TimeText.compact(week.totalMinutes)) total, \(TimeText.compact(week.averageMinutes)) daily average")
                .accessibilityIdentifier("device-week-chart-\(device.id.uuidString)")
            }
        }
        .brightCard()
    }

    private func weeklyMetric(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func axisTime(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

// MARK: - Device detail

/// Everything about one device: today vs averages, and who used it this week.
struct DeviceDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let device: Device
    let children: [ChildProfile]
    let sessions: [UsageSession]

    @State private var isEditingDevice = false

    var body: some View {
        let color = AppTheme.color(forDeviceID: device.id)
        let usage = weeklyUsageByChild

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: device.kind.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 52, height: 52)
                        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text(device.isShared ? "Shared household device" : "Used by \(device.child?.name ?? "Unassigned")")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 2)

                HStack(spacing: 8) {
                    ForEach(metrics) { metric in
                        StatTile(
                            label: metric.title,
                            value: TimeText.compact(metric.minutes),
                            detail: metric.isAboveAverage ? "↑ above usual" : "usual",
                            detailColor: metric.isAboveAverage ? AppTheme.dangerText : AppTheme.textSecondary
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(
                        title: "Who used it this week",
                        detail: usage.first.map { "Most: \($0.child.name)" }
                    )

                    if usage.isEmpty {
                        Text("No usage recorded this week.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Chart(usage) { point in
                            BarMark(
                                x: .value("Kid", point.child.name),
                                y: .value("Minutes", point.minutes)
                            )
                            .foregroundStyle(point.child.color.color)
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                Text(TimeText.compact(point.minutes))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .chartYAxis(.hidden)
                        .chartLegend(.hidden)
                        .frame(height: 170)
                    }
                }
                .brightCard()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Weekly usage by kid")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isEditingDevice = true
                }
                .accessibilityIdentifier("edit-device-button")
            }
        }
        .sheet(isPresented: $isEditingDevice) {
            DeviceFormView(children: children, device: device)
        }
        .onChange(of: device.isActive) { _, isActive in
            if !isActive { dismiss() }
        }
        .accessibilityIdentifier("device-analysis-card-\(device.id.uuidString)")
    }

    private var metrics: [DeviceMetric] {
        let calendar = AppCalendar.day
        let today = UsageAggregator.totalMinutes(on: .now, deviceID: device.id, sessions: sessions, calendar: calendar)
        let priorAverage = DeviceStats.priorDailyAverage(for: device, sessions: sessions, dayCount: 7)
        let week = DeviceStats.analysis(for: device, period: .week, children: children, sessions: sessions)
        let month = DeviceStats.analysis(for: device, period: .month, children: children, sessions: sessions)
        let weekDays = DeviceStats.elapsedDayCount(in: .weekOfYear, calendar: calendar)
        let monthDays = DeviceStats.elapsedDayCount(in: .month, calendar: calendar)

        return [
            DeviceMetric(title: "Today", minutes: today, isAboveAverage: today > priorAverage),
            DeviceMetric(
                title: "Week avg",
                minutes: week.dailyAverageMinutes,
                isAboveAverage: week.dailyAverageMinutes > week.previousMinutes / max(weekDays, 1)
            ),
            DeviceMetric(
                title: "Month avg",
                minutes: month.dailyAverageMinutes,
                isAboveAverage: month.dailyAverageMinutes > month.previousMinutes / max(monthDays, 1)
            )
        ]
    }

    private var weeklyUsageByChild: [ChildDeviceUsage] {
        guard let week = AppCalendar.day.dateInterval(of: .weekOfYear, for: .now) else { return [] }

        return children
            .compactMap { child in
                let minutes = sessions
                    .filter { $0.device?.id == device.id && $0.child?.id == child.id && week.contains($0.startedAt) }
                    .reduce(0) { $0 + $1.durationMinutes }
                return minutes > 0 ? ChildDeviceUsage(child: child, minutes: minutes) : nil
            }
            .sorted { lhs, rhs in
                if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
                return lhs.child.name.localizedCaseInsensitiveCompare(rhs.child.name) == .orderedAscending
            }
    }
}

private struct ChildDeviceUsage: Identifiable {
    let child: ChildProfile
    let minutes: Int
    var id: UUID { child.id }
}

private struct DeviceMetric: Identifiable {
    let title: String
    let minutes: Int
    let isAboveAverage: Bool
    var id: String { title }
}

// MARK: - Shared device math

struct DeviceTrendPoint: Identifiable {
    let date: Date
    let minutes: Int
    var id: Date { date }
}

struct DeviceWeekSummary {
    let interval: DateInterval
    let points: [DeviceTrendPoint]
    let totalMinutes: Int
    let averageMinutes: Int
}

enum DeviceStats {
    static func currentWeek(
        for device: Device,
        sessions: [UsageSession],
        now: Date = .now,
        calendar: Calendar = AppCalendar.day
    ) -> DeviceWeekSummary {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
            return DeviceWeekSummary(
                interval: DateInterval(start: start, end: end),
                points: [],
                totalMinutes: 0,
                averageMinutes: 0
            )
        }

        let today = calendar.startOfDay(for: now)
        var day = interval.start
        var points: [DeviceTrendPoint] = []

        while day < interval.end {
            points.append(
                DeviceTrendPoint(
                    date: day,
                    minutes: UsageAggregator.totalMinutes(
                        on: day,
                        deviceID: device.id,
                        sessions: sessions,
                        calendar: calendar
                    )
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let elapsed = points.filter { $0.date <= today }
        let total = elapsed.reduce(0) { $0 + $1.minutes }
        return DeviceWeekSummary(
            interval: interval,
            points: points,
            totalMinutes: total,
            averageMinutes: elapsed.isEmpty ? 0 : total / elapsed.count
        )
    }

    static func analysis(
        for device: Device,
        period: AnalysisPeriod,
        children: [ChildProfile],
        sessions: [UsageSession]
    ) -> PeriodAnalysis {
        let childIDs = device.isShared
            ? Set(children.map(\.id))
            : Set(device.child.map { [$0.id] } ?? [])

        return AnalysisCalculator.analyze(
            period: period,
            now: .now,
            childIDs: childIDs,
            sessions: sessions.filter { $0.device?.id == device.id },
            devices: [device]
        )
    }

    static func weekAnalysis(for device: Device, children: [ChildProfile], sessions: [UsageSession]) -> PeriodAnalysis {
        analysis(for: device, period: .week, children: children, sessions: sessions)
    }

    /// Average per day over the `dayCount` completed days before today.
    static func priorDailyAverage(for device: Device, sessions: [UsageSession], dayCount: Int) -> Int {
        let calendar = AppCalendar.day
        let todayStart = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -dayCount, to: todayStart) else { return 0 }
        let total = sessions
            .filter { $0.device?.id == device.id && $0.startedAt >= start && $0.startedAt < todayStart }
            .reduce(0) { $0 + $1.durationMinutes }
        return total / max(dayCount, 1)
    }

    /// Per-day totals for the last seven days, today included (for sparklines).
    static func lastSevenDays(for device: Device, sessions: [UsageSession]) -> [DeviceTrendPoint] {
        let calendar = AppCalendar.day
        let todayStart = calendar.startOfDay(for: .now)
        let deviceSessions = sessions.filter { $0.device?.id == device.id }

        return (0..<7).reversed().compactMap { daysAgo in
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) else { return nil }
            let minutes = UsageAggregator.totalMinutes(on: day, deviceID: device.id, sessions: deviceSessions, calendar: calendar)
            return DeviceTrendPoint(date: day, minutes: minutes)
        }
    }

    static func elapsedDayCount(in component: Calendar.Component, calendar: Calendar) -> Int {
        let now = Date.now
        guard let interval = calendar.dateInterval(of: component, for: now) else { return 1 }
        return max((calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day ?? 0) + 1, 1)
    }
}
