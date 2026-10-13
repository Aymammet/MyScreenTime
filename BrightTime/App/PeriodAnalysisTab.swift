import Charts
import SwiftData
import SwiftUI

/// The Weekly and Monthly tabs. Same data, two lenses: a bar chart with the limit
/// drawn in for a week, a calendar heatmap for a month. ‹ › steps back through
/// earlier periods.
struct PeriodAnalysisTab: View {
    let period: AnalysisPeriod
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]

    @State private var offset = 0
    @State private var selectedDay: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0

    private var calendar: Calendar { AppCalendar.day }

    // MARK: - Period math

    private var interval: DateInterval {
        let shifted = calendar.date(byAdding: period.calendarComponent, value: offset, to: .now) ?? .now
        return calendar.dateInterval(of: period.calendarComponent, for: shifted)
            ?? DateInterval(start: calendar.startOfDay(for: .now), duration: 86_400)
    }

    /// "Now" for the selected period: today for the current one, the period's last
    /// second for past ones, so past weeks and months are counted in full.
    private var referenceDate: Date {
        offset == 0 ? .now : interval.end.addingTimeInterval(-1)
    }

    private var childIDs: Set<UUID> {
        Set(children.map(\.id))
    }

    private func makeAnalysis() -> PeriodAnalysis {
        AnalysisCalculator.analyze(
            period: period,
            now: referenceDate,
            childIDs: childIDs,
            sessions: sessions,
            devices: devices
        )
    }

    /// Every day of the period, with nil minutes for days that haven't happened yet.
    private func makeDays(from analysis: PeriodAnalysis) -> [DayUsage] {
        let points = analysis.dailyPoints
        var result: [DayUsage] = []
        var day = interval.start
        while day < interval.end {
            let minutes = points.first { calendar.isDate($0.date, inSameDayAs: day) }?.minutes
            result.append(DayUsage(date: day, minutes: minutes, limit: familyLimit(on: day)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private func familyLimit(on day: Date) -> Int {
        children.reduce(0) { $0 + $1.limitMinutes(on: day, calendar: calendar) }
    }

    private var periodTitle: String {
        switch period {
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            let start = interval.start.formatted(.dateTime.month(.abbreviated).day())
            let end = last.formatted(.dateTime.month(.abbreviated).day())
            return "\(start) – \(end)"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        }
    }

    private func step(by delta: Int) {
        withAnimation(AppTheme.motion(reduceMotion: reduceMotion)) {
            offset = min(offset + delta, 0)
            selectedDay = nil
        }
    }

    // MARK: - Body

    var body: some View {
        let _ = calendarRevision
        let analysis = makeAnalysis()
        let days = makeDays(from: analysis)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PeriodStepper(
                    title: periodTitle,
                    canGoForward: offset < 0,
                    onBack: { step(by: -1) },
                    onForward: { step(by: 1) }
                )

                summaryTiles(analysis: analysis, days: days)

                switch period {
                case .week:
                    kidDailyCharts
                case .month:
                    streakCard(analysis: analysis, days: days)
                    heatmapCard(days: days)
                }

                byChildCard
                todayDeviceUsageCard

                if period == .month {
                    highlightTiles(days: days)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, AppTheme.tabBarContentClearance)
            .scrollTopAnchor()
        }
        .scrollsToTopOnTabReselect()
        .sensoryFeedback(.selection, trigger: offset)
    }

    // MARK: - Summary

    private func summaryTiles(analysis: PeriodAnalysis, days: [DayUsage]) -> some View {
        let elapsed = days.filter { $0.minutes != nil }
        // Only days that had a limit can be "on track"; with no limits set it's "—".
        let limitedDays = elapsed.filter { $0.limit > 0 }
        let onTrack = limitedDays.filter { $0.status == .normal }.count
        let averageLimit = elapsed.isEmpty ? 0 : elapsed.reduce(0) { $0 + $1.limit } / elapsed.count

        return HStack(spacing: 8) {
            StatTile(
                label: "Total",
                value: TimeText.compact(analysis.currentMinutes),
                detail: TimeText.change(analysis.changePercent) ?? "No earlier data",
                detailColor: TimeText.changeColor(analysis.changePercent)
            )
            StatTile(
                label: "Daily avg",
                value: TimeText.compact(analysis.dailyAverageMinutes),
                detail: averageLimit > 0 ? "limit \(TimeText.compact(averageLimit))" : "no limit set"
            )
            StatTile(
                label: "On track",
                value: limitedDays.isEmpty ? "—" : "\(onTrack) / \(limitedDays.count)",
                detail: limitedDays.isEmpty ? "no limits yet" : "days",
                detailColor: limitedDays.isEmpty ? AppTheme.textSecondary : AppTheme.primary
            )
        }
    }

    // MARK: - Week chart

    private var kidDailyCharts: some View {
        Group {
            if children.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Daily usage by kid")
                    emptyMessage("Add a kid to see daily usage and limits.")
                }
                .brightCard()
            } else {
                ForEach(children) { child in
                    kidDailyChartCard(child)
                }
            }
        }
    }

    private func days(for child: ChildProfile) -> [DayUsage] {
        var result: [DayUsage] = []
        var day = interval.start
        let lastVisibleDay = calendar.startOfDay(for: referenceDate)

        while day < interval.end {
            let minutes = day <= lastVisibleDay
                ? UsageAggregator.totalMinutes(on: day, childID: child.id, sessions: sessions, calendar: calendar)
                : nil
            result.append(
                DayUsage(
                    date: day,
                    minutes: minutes,
                    limit: child.limitMinutes(on: day, calendar: calendar)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private func kidDailyChartCard(_ child: ChildProfile) -> some View {
        let allDays = days(for: child)
        let selected = selectedDay.flatMap { date in allDays.first { calendar.isDate($0.date, inSameDayAs: date) } }
        let hasLimit = allDays.contains { $0.limit > 0 }
        let hasUsage = allDays.contains { ($0.minutes ?? 0) > 0 }
        let total = allDays.compactMap(\.minutes).reduce(0, +)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ChildAvatarView(child: child, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(child.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryDeep)
                    Text("Daily usage · \(TimeText.compact(total)) week total")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 8)
                if let detail = selectedDetail(selected) {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.trailing)
                } else if hasUsage {
                    Text("Tap a bar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if hasUsage || hasLimit {
                Chart {
                    ForEach(allDays) { day in
                        if let minutes = day.minutes {
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", minutes)
                            )
                            .foregroundStyle(barColor(for: day))
                            .opacity(selected == nil || selected?.id == day.id ? 1 : 0.45)
                            .cornerRadius(6)
                        }
                    }

                    if hasLimit {
                        ForEach(allDays) { day in
                            LineMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Limit", day.limit),
                                series: .value("Series", "Limit")
                            )
                            .interpolationMethod(.stepCenter)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .foregroundStyle(AppTheme.success)
                        }
                    }
                }
                .chartXScale(domain: interval.start...interval.end)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(AppTheme.cardBorder)
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedDay)
                .frame(height: 190)
                .accessibilityIdentifier("usage-trend-chart-\(child.id.uuidString)")

                if hasLimit {
                    kidChartLegend
                }
            } else {
                emptyMessage("No usage recorded this week.")
            }
        }
        .brightCard()
    }

    private var kidChartLegend: some View {
        HStack(spacing: 10) {
            legendItem(color: AppTheme.primarySoft, text: "On track")
            legendItem(color: AppTheme.warning, text: "Near limit")
            legendItem(color: AppTheme.danger, text: "Over")
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Capsule()
                    .fill(AppTheme.success)
                    .frame(width: 20, height: 2)
                Text("Daily limit")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private func barColor(for day: DayUsage) -> Color {
        switch day.status {
        case .exceeded: AppTheme.danger
        case .nearLimit, .reached: AppTheme.warning
        case .normal: calendar.isDateInToday(day.date) ? AppTheme.primary : AppTheme.primarySoft
        }
    }

    private func selectedDetail(_ day: DayUsage?) -> String? {
        guard let day, let minutes = day.minutes else { return nil }
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        var text = "\(date) · \(TimeText.compact(minutes))"
        if day.limit > 0, minutes > day.limit {
            text += " · \(TimeText.compact(minutes - day.limit)) over"
        }
        return text
    }

    // MARK: - Month

    private func streakCard(analysis: PeriodAnalysis, days: [DayUsage]) -> some View {
        let streak = currentStreak(in: days)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Total this month")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(TimeText.compact(analysis.currentMinutes))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .contentTransition(.numericText())
                if let change = TimeText.change(analysis.changePercent) {
                    Text(change)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TimeText.changeColor(analysis.changePercent))
                }
            }

            Spacer(minLength: 8)

            if streak >= 2 {
                VStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppTheme.warning)
                        .symbolEffect(.bounce, value: streak)
                    Text("\(streak)-day streak")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.primaryDeep)
                    Text("under limit")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .brightCard()
    }

    /// Consecutive days, counting back from the latest one, that stayed within limits.
    private func currentStreak(in days: [DayUsage]) -> Int {
        var count = 0
        for day in days.filter({ $0.minutes != nil }).reversed() {
            guard day.limit > 0, day.status == .normal else { break }
            count += 1
        }
        return count
    }

    private func heatmapCard(days allDays: [DayUsage]) -> some View {
        let maxMinutes = max(allDays.compactMap(\.minutes).max() ?? 0, 1)
        let leadingBlanks = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        let selected = selectedDay.flatMap { date in allDays.first { calendar.isDate($0.date, inSameDayAs: date) } }

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Every day", detail: selectedDetail(selected) ?? "Darker = more time")

            LazyVGrid(columns: columns, spacing: 5) {
                // Headers and blanks get string IDs ("weekday-0", "blank-0") so they can't
                // collide with each other inside the one grid (Int IDs did).
                ForEach(weekdayHeaders) { header in
                    Text(header.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                ForEach((0..<leadingBlanks).map { "blank-\($0)" }, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(allDays) { day in
                    heatCell(day, maxMinutes: maxMinutes, isSelected: selected?.id == day.id)
                }
            }

            HStack(spacing: 4) {
                Text("Less")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatColor(level: level))
                        .frame(width: 11, height: 11)
                }
                Text("More")
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(AppTheme.danger, lineWidth: 2)
                    .frame(width: 11, height: 11)
                Text("Over limit")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .brightCard()
    }

    private var weekdayHeaders: [WeekdayHeader] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return ordered.enumerated().map { WeekdayHeader(index: $0.offset, symbol: $0.element) }
    }

    private func heatCell(_ day: DayUsage, maxMinutes: Int, isSelected: Bool) -> some View {
        let minutes = day.minutes ?? 0
        let level = day.minutes == nil ? 0 : heatLevel(minutes: minutes, maxMinutes: maxMinutes)
        let isOver = day.limit > 0 && minutes > day.limit
        let dayNumber = calendar.component(.day, from: day.date)
        let spokenValue: String = day.minutes == nil
            ? "No data yet"
            : TimeText.compact(minutes) + (isOver ? ", over limit" : "")

        return Button {
            withAnimation(AppTheme.motion(reduceMotion: reduceMotion)) {
                selectedDay = isSelected ? nil : day.date
            }
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(heatColor(level: level))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("\(dayNumber)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(level >= 4 ? Color.white : (level == 3 ? AppTheme.primaryDeep : AppTheme.textSecondary))
                }
                .overlay {
                    if isOver {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(AppTheme.danger, lineWidth: 2)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(AppTheme.primaryDeep, lineWidth: 2)
                    }
                }
                .opacity(day.minutes == nil ? 0.4 : 1)
                .scaleEffect(isSelected ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .disabled(day.minutes == nil)
        .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue(spokenValue)
    }

    private func heatLevel(minutes: Int, maxMinutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        let ratio = Double(minutes) / Double(maxMinutes)
        switch ratio {
        case ..<0.25: return 1
        case ..<0.5: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }

    private func heatColor(level: Int) -> Color {
        switch level {
        case 0: AppTheme.surfaceMuted
        case 1: AppTheme.primaryTint
        case 2: AppTheme.primarySoft
        case 3: AppTheme.heatMid
        default: AppTheme.primary
        }
    }

    private func highlightTiles(days: [DayUsage]) -> some View {
        let used = days.filter { ($0.minutes ?? 0) > 0 }
        let calmest = used.min { ($0.minutes ?? 0) < ($1.minutes ?? 0) }
        let busiest = used.max { ($0.minutes ?? 0) < ($1.minutes ?? 0) }

        return HStack(spacing: 8) {
            StatTile(
                label: "Calmest day",
                value: calmest.map { $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "—",
                detail: calmest.map { "\(TimeText.compact($0.minutes ?? 0)) total" },
                detailColor: AppTheme.primary
            )
            StatTile(
                label: "Busiest day",
                value: busiest.map { $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "—",
                detail: busiest.map { "\(TimeText.compact($0.minutes ?? 0)) total" },
                detailColor: busiest?.status == .exceeded ? AppTheme.dangerText : AppTheme.textSecondary
            )
        }
    }

    // MARK: - Breakdowns

    private var byChildCard: some View {
        let previous: DateInterval = {
            let start = calendar.date(byAdding: period.calendarComponent, value: -1, to: interval.start) ?? interval.start
            return DateInterval(start: start, end: interval.start)
        }()
        let previousDayCount = max(calendar.dateComponents([.day], from: previous.start, to: previous.end).day ?? 1, 1)

        let rows = children.map { child in
            let elapsed = days(for: child).compactMap { day in day.minutes.map { (minutes: $0, limit: day.limit) } }
            let dayCount = max(elapsed.count, 1)
            let previousTotal = UsageAggregator.totalMinutes(in: previous, childIDs: [child.id], sessions: sessions)
            return ChildAverage(
                child: child,
                minutes: elapsed.reduce(0) { $0 + $1.minutes } / dayCount,
                limit: elapsed.reduce(0) { $0 + $1.limit } / dayCount,
                lightest: elapsed.map { $0.minutes }.min() ?? 0,
                busiest: elapsed.map { $0.minutes }.max() ?? 0,
                daysCounted: elapsed.count,
                previousMinutes: previousTotal > 0 ? previousTotal / previousDayCount : nil
            )
        }
        .sorted { $0.minutes > $1.minutes }

        // One shared scale, so kids can be compared fairly.
        let scaleMax = max(rows.map { max($0.busiest, $0.limit, $0.minutes) }.max() ?? 0, 60)
        let comparisonLabel = period == .week ? "vs last week" : "vs last month"

        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Daily average by kid", detail: period == .week ? "This week" : "This month")

            if rows.isEmpty {
                emptyMessage("Add a kid to see their daily average.")
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(AppTheme.cardBorder) }
                    AverageRangeRow(
                        row: row,
                        scaleMax: Double(scaleMax) * 1.08,
                        color: averageColor(row),
                        comparisonLabel: comparisonLabel
                    )
                }
                AverageRangeLegend()
            }
        }
        .brightCard()
        .accessibilityIdentifier("daily-average-by-kid")
    }

    private func averageColor(_ row: ChildAverage) -> Color {
        guard row.limit > 0 else { return AppTheme.textSecondary }
        if row.minutes > row.limit { return AppTheme.danger }
        if row.minutes * 100 >= row.limit * 80 { return AppTheme.warning }
        return AppTheme.success
    }

    private var todayDeviceUsageCard: some View {
        let groups = children.map { child in
            KidTodayDeviceGroup(
                child: child,
                rows: devices.compactMap { device in
                    let minutes = UsageAggregator.totalMinutes(
                        on: .now,
                        childID: child.id,
                        deviceID: device.id,
                        sessions: sessions,
                        calendar: calendar
                    )
                    return minutes > 0 ? KidTodayDeviceRow(device: device, minutes: minutes) : nil
                }
                .sorted { lhs, rhs in
                    if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
                    return lhs.device.name.localizedCaseInsensitiveCompare(rhs.device.name) == .orderedAscending
                }
            )
        }

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Kid device usage", detail: "Today")

            if groups.isEmpty {
                emptyMessage("Add a kid to see their device usage.")
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 9) {
                            ChildAvatarView(child: group.child, size: 30)
                            Text(group.child.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.primaryDeep)
                            Spacer()
                            Text(TimeText.compact(group.totalMinutes))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(group.totalMinutes > group.child.limitMinutes(on: .now, calendar: calendar) ? AppTheme.dangerText : AppTheme.primary)
                        }

                        if group.rows.isEmpty {
                            Text("No device usage recorded today.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.leading, 39)
                        } else {
                            ForEach(group.rows) { row in
                                HStack(spacing: 9) {
                                    Image(systemName: row.device.kind.systemImage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.color(forDeviceID: row.device.id))
                                        .frame(width: 28, height: 28)
                                        .background(AppTheme.color(forDeviceID: row.device.id).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    Text(row.device.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.primaryDeep)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(TimeText.compact(row.minutes))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .padding(.leading, 39)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    if group.id != groups.last?.id {
                        Divider().overlay(AppTheme.cardBorder)
                    }
                }
            }
        }
        .brightCard()
        .accessibilityIdentifier("kid-device-usage-today")
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct WeekdayHeader: Identifiable {
    let index: Int
    let symbol: String
    var id: String { "weekday-\(index)" }
}

private struct ChildAverage: Identifiable {
    let child: ChildProfile
    /// Average minutes per day over the days counted so far.
    let minutes: Int
    /// Average daily limit over the same days.
    let limit: Int
    let lightest: Int
    let busiest: Int
    let daysCounted: Int
    /// Average per day in the previous week or month; nil when nothing was logged.
    let previousMinutes: Int?
    var id: UUID { child.id }

    enum Status { case over, close, within, noLimit }

    var status: Status {
        guard limit > 0 else { return .noLimit }
        if minutes > limit { return .over }
        if minutes * 100 >= limit * 80 { return .close }
        return .within
    }
}

/// One kid in "Daily average by kid": the average as a dot, the lightest to
/// busiest day as a line through it, and the limit as a tick, on a scale shared
/// by every kid in the card.
private struct AverageRangeRow: View {
    let row: ChildAverage
    let scaleMax: Double
    let color: Color
    let comparisonLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ChildAvatarView(child: row.child, size: 26)
                Text(row.child.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .lineLimit(1)
                statusChip
                Spacer(minLength: 4)
                Text(TimeText.compact(row.minutes))
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(row.status == .noLimit ? AppTheme.primaryDeep : color)
                    .contentTransition(.numericText())
            }

            track
                .frame(height: row.limit > 0 ? 44 : 36)

            caption
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (minutes: Int) -> CGFloat in
                min(max(CGFloat(Double(minutes) / scaleMax) * width, 0), width)
            }
            let barTop: CGFloat = 24
            let barMid = barTop + 6

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(AppTheme.surfaceMuted)
                    .frame(width: width, height: 12)
                    .offset(y: barTop)

                if row.limit > 0 {
                    Capsule()
                        .fill(AppTheme.primary.opacity(0.22))
                        .frame(width: x(row.limit), height: 12)
                        .offset(y: barTop)
                }

                if row.daysCounted > 1, row.busiest > row.lightest {
                    Capsule()
                        .fill(color.opacity(0.6))
                        .frame(width: max(x(row.busiest) - x(row.lightest), 3), height: 3)
                        .offset(x: x(row.lightest), y: barMid - 1.5)
                }

                if row.limit > 0 {
                    // The limit: a bright line from the tag down through the bar.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.primaryDeep)
                        .frame(width: 3, height: 26)
                        .offset(x: x(row.limit) - 1.5, y: 16)

                    limitTag
                        .position(x: tagCenter(limitX: x(row.limit), width: width), y: 8.5)
                }

                Circle()
                    .fill(color)
                    .frame(width: 15, height: 15)
                    .overlay { Circle().stroke(AppTheme.surface, lineWidth: 2.5) }
                    .offset(x: x(row.minutes) - 7.5, y: barMid - 7.5)
            }
        }
    }

    private var limitText: String {
        "Limit \(TimeText.compact(row.limit))"
    }

    /// "Limit 2h" above the limit line. Sits above the bar so it never covers
    /// the average dot.
    private var limitTag: some View {
        Text(limitText)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(AppTheme.background)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 17)
            .background(AppTheme.primaryDeep, in: Capsule())
    }

    /// Centres the tag on the limit, sliding it inward near either edge so it
    /// never gets cut off.
    private func tagCenter(limitX: CGFloat, width: CGFloat) -> CGFloat {
        let tagWidth = CGFloat(limitText.count) * 6.4 + 16
        let half = tagWidth / 2
        return min(max(limitX, half), max(width - half, half))
    }

    private var chipText: String {
        switch row.status {
        case .over: "\(TimeText.compact(row.minutes - row.limit)) over"
        case .close: "Close to limit"
        case .within: "Well within"
        case .noLimit: "No limit"
        }
    }

    private var chipTint: Color {
        switch row.status {
        case .over: AppTheme.dangerText
        case .close: AppTheme.warningText
        case .within: AppTheme.primary
        case .noLimit: AppTheme.textSecondary
        }
    }

    private var statusChip: some View {
        let tint = chipTint
        return Text(chipText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    private var caption: Text {
        var parts: [Text] = []
        if row.daysCounted > 1 {
            parts.append(Text("Days ranged ") + Text("\(TimeText.compact(row.lightest)) – \(TimeText.compact(row.busiest))").bold())
        } else {
            parts.append(Text(row.daysCounted == 1 ? "1 day so far" : "No days yet"))
        }
        if row.limit == 0 {
            parts.append(Text("no limit set"))
        }
        if let previous = row.previousMinutes {
            let change = row.minutes - previous
            if change != 0 {
                let arrow = change > 0 ? "↑" : "↓"
                let tint = change > 0 ? AppTheme.dangerText : AppTheme.primary
                parts.append(Text("\(arrow) \(TimeText.compact(abs(change)))").bold().foregroundStyle(tint) + Text(" \(comparisonLabel)"))
            } else {
                parts.append(Text("same as \(comparisonLabel.replacingOccurrences(of: "vs ", with: ""))"))
            }
        }
        return parts.dropFirst().reduce(parts.first ?? Text("")) { $0 + Text(" · ") + $1 }
    }

    private var accessibilityText: String {
        var text = "\(row.child.name), average \(TimeText.spoken(row.minutes)) a day"
        switch row.status {
        case .over: text += ", \(TimeText.spoken(row.minutes - row.limit)) over a \(TimeText.spoken(row.limit)) limit"
        case .close, .within: text += ", limit \(TimeText.spoken(row.limit))"
        case .noLimit: text += ", no limit set"
        }
        if row.daysCounted > 1 {
            text += ". Lightest day \(TimeText.spoken(row.lightest)), busiest \(TimeText.spoken(row.busiest))"
        }
        if let previous = row.previousMinutes, previous != row.minutes {
            let change = row.minutes - previous
            text += ". \(change > 0 ? "Up" : "Down") \(TimeText.spoken(abs(change))) \(comparisonLabel)"
        }
        return text
    }
}

/// Key for the dot, range line and limit tick.
private struct AverageRangeLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            item("average") { Circle().fill(AppTheme.textSecondary).frame(width: 8, height: 8) }
            item("lightest – busiest") { Capsule().fill(AppTheme.textSecondary).frame(width: 14, height: 3) }
            item("within limit") { Capsule().fill(AppTheme.primary.opacity(0.35)).frame(width: 14, height: 7) }
        }
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
        .accessibilityHidden(true)
    }

    private func item<Mark: View>(_ label: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 4) {
            mark()
            Text(label).lineLimit(1)
        }
    }
}

private struct KidTodayDeviceGroup: Identifiable {
    let child: ChildProfile
    let rows: [KidTodayDeviceRow]

    var id: UUID { child.id }
    var totalMinutes: Int { rows.reduce(0) { $0 + $1.minutes } }
}

private struct KidTodayDeviceRow: Identifiable {
    let device: Device
    let minutes: Int

    var id: UUID { device.id }
}

/// One day of family usage. `minutes` is nil for days that haven't happened yet.
private struct DayUsage: Identifiable {
    let date: Date
    let minutes: Int?
    let limit: Int

    var id: Date { date }

    var status: DailyLimitStatus {
        guard let minutes, limit > 0 else { return .normal }
        return DailyUsageSummary(usedMinutes: minutes, limitMinutes: limit).status
    }
}
