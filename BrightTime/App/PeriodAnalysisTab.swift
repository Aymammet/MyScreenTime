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

    private var calendar: Calendar { .current }

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

    private var countedInterval: DateInterval {
        let endOfReferenceDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? interval.end
        return DateInterval(start: interval.start, end: min(endOfReferenceDay, interval.end))
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
                    dailyChartCard(days: days)
                case .month:
                    streakCard(analysis: analysis, days: days)
                    heatmapCard(days: days)
                }

                byChildCard
                byDeviceCard(analysis: analysis)

                if period == .month {
                    highlightTiles(days: days)
                }

                DailyInsightsCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .sensoryFeedback(.selection, trigger: offset)
    }

    // MARK: - Summary

    private func summaryTiles(analysis: PeriodAnalysis, days: [DayUsage]) -> some View {
        let elapsed = days.filter { $0.minutes != nil }
        let onTrack = elapsed.filter { $0.status == .normal }.count
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
                value: "\(onTrack) / \(elapsed.count)",
                detail: "days",
                detailColor: AppTheme.primary
            )
        }
    }

    // MARK: - Week chart

    private func dailyChartCard(days allDays: [DayUsage]) -> some View {
        let selected = selectedDay.flatMap { date in allDays.first { calendar.isDate($0.date, inSameDayAs: date) } }
        let hasLimit = allDays.contains { $0.limit > 0 }
        let hasUsage = allDays.contains { ($0.minutes ?? 0) > 0 }

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Daily usage", detail: selectedDetail(selected) ?? "Tap a bar")

            if hasUsage {
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
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(AppTheme.textTertiary)
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
                .accessibilityIdentifier("usage-trend-chart")

                if hasLimit {
                    legendRow
                }
            } else {
                emptyMessage("No usage recorded this week.")
            }
        }
        .brightCard()
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            legendItem(color: AppTheme.primarySoft, text: "On track")
            legendItem(color: AppTheme.warning, text: "Near limit")
            legendItem(color: AppTheme.danger, text: "Over")
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
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
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

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
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
                        .foregroundStyle(level >= 3 ? Color.white : AppTheme.textSecondary)
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
        case 3: Color(hex: 0x5FB0A9)
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
        let counted = countedInterval
        let rows = children
            .map { child in
                ChildShare(child: child, minutes: UsageAggregator.totalMinutes(in: counted, childIDs: [child.id], sessions: sessions))
            }
            .sorted { $0.minutes > $1.minutes }
        let maxMinutes = max(rows.map(\.minutes).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "By child")

            if rows.isEmpty {
                emptyMessage("Add a child to see their share.")
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        ChildAvatarView(child: row.child, size: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.child.name)
                                Spacer()
                                Text(TimeText.compact(row.minutes))
                                    .contentTransition(.numericText())
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.primaryDeep)

                            LimitBar(
                                progress: Double(row.minutes) / Double(maxMinutes),
                                color: row.child.color.color
                            )
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .brightCard()
    }

    private func byDeviceCard(analysis: PeriodAnalysis) -> some View {
        let points = analysis.devicePoints
        let total = max(points.reduce(0) { $0 + $1.minutes }, 1)

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "By device", detail: points.isEmpty ? nil : TimeText.compact(analysis.currentMinutes))

            if points.isEmpty {
                emptyMessage("Device usage appears after a session is recorded.")
            } else {
                GeometryReader { proxy in
                    let spacing: CGFloat = 2
                    let available = proxy.size.width - spacing * CGFloat(points.count - 1)
                    HStack(spacing: spacing) {
                        ForEach(points) { point in
                            Rectangle()
                                .fill(AppTheme.color(forDeviceID: point.deviceID))
                                .frame(width: max(available * CGFloat(point.minutes) / CGFloat(total), 2))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                .accessibilityHidden(true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(points) { point in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.color(forDeviceID: point.deviceID))
                                .frame(width: 8, height: 8)
                            Text(point.name)
                                .lineLimit(1)
                            Text("\(Int((Double(point.minutes) / Double(total) * 100).rounded()))%")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("device-breakdown-chart")
            }
        }
        .brightCard()
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct ChildShare: Identifiable {
    let child: ChildProfile
    let minutes: Int
    var id: UUID { child.id }
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
