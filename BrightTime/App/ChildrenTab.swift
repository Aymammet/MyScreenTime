import Charts
import SwiftData
import SwiftUI

/// One child at a time: pick them with avatar chips, see today inside a sun-ring,
/// adjust weekday/weekend limits right here, then their week or month and devices.
struct ChildrenTab: View {
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedChildID: UUID?
    @State private var period: AnalysisPeriod = .week
    @State private var childToEdit: ChildProfile?

    private var selectedChild: ChildProfile? {
        children.first { $0.id == selectedChildID } ?? children.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if children.isEmpty {
                    emptyCard
                } else {
                    childPicker

                    if let child = selectedChild {
                        Group {
                            profileCard(child)
                            limitsCard(child)
                            periodCard(child)
                            devicesCard(child)
                        }
                        .id(child.id)
                        .transition(.opacity)
                    }
                }

                DailyInsightsCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .animation(AppTheme.motion(reduceMotion: reduceMotion), value: selectedChild?.id)
        }
        .sensoryFeedback(.selection, trigger: selectedChildID)
        .sheet(
            isPresented: Binding(
                get: { childToEdit != nil },
                set: { if !$0 { childToEdit = nil } }
            )
        ) {
            if let childToEdit, let parent = childToEdit.parent {
                ChildFormView(parent: parent, child: childToEdit)
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 64, height: 64)
                .background(AppTheme.primaryTint, in: Circle())
            Text("No children to show")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            Text("Add a child on the Home tab to see their limits, trends and devices here.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .brightCard(padding: 24)
    }

    // MARK: - Picker

    private var childPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(children) { child in
                    let isSelected = child.id == selectedChild?.id

                    Button {
                        selectedChildID = child.id
                    } label: {
                        HStack(spacing: 7) {
                            ChildAvatarView(child: child, size: 28)
                            Text(child.name)
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? Color.white : AppTheme.primaryDeep)
                        .padding(.leading, 4)
                        .padding(.trailing, 14)
                        .padding(.vertical, 4)
                        .background(isSelected ? AppTheme.primary : AppTheme.surface, in: Capsule())
                        .overlay {
                            Capsule().stroke(isSelected ? Color.clear : AppTheme.cardBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Today

    private func profileCard(_ child: ChildProfile) -> some View {
        let summary = UsageAggregator.summary(on: .now, child: child, sessions: sessions)
        let color = AppTheme.statusColor(for: summary.status)

        return VStack(spacing: 8) {
            SunRingView(
                progress: summary.progress,
                color: color,
                rayColor: color.opacity(0.4),
                size: 168,
                lineWidth: 12
            ) {
                ChildAvatarView(child: child, size: 94)
            }

            Text(child.name)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.primaryDeep)

            Text("\(TimeText.compact(summary.usedMinutes)) of \(TimeText.compact(summary.limitMinutes)) today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .contentTransition(.numericText())

            BrightChip.status(statusText(summary), summary.status)
        }
        .frame(maxWidth: .infinity)
        .brightCard(padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(child.name) today")
        .accessibilityValue("\(TimeText.compact(summary.usedMinutes)) of \(TimeText.compact(summary.limitMinutes)). \(statusText(summary))")
    }

    private func statusText(_ summary: DailyUsageSummary) -> String {
        switch summary.status {
        case .normal: "On track · \(TimeText.compact(summary.remainingMinutes)) left"
        case .nearLimit: "Near limit · \(TimeText.compact(summary.remainingMinutes)) left"
        case .reached: "Limit reached"
        case .exceeded: "\(TimeText.compact(summary.overMinutes)) over limit"
        }
    }

    // MARK: - Limits

    private enum LimitKind {
        case everyDay, weekdays, weekends
    }

    private func limitsCard(_ child: ChildProfile) -> some View {
        let hasSchedule = child.weekdayLimitMinutes != nil && child.weekendLimitMinutes != nil
        let isWeekend = Calendar.current.isDateInWeekend(.now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily limits")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                Spacer()
                Button("Edit") { childToEdit = child }
                    .font(.footnote.bold())
                    .accessibilityLabel("Edit \(child.name)'s profile and limits")
                    .accessibilityIdentifier("children-edit-limit-\(child.id.uuidString)")
            }

            if hasSchedule {
                HStack(spacing: 8) {
                    limitTile(child, kind: .weekdays, title: "Weekdays", isToday: !isWeekend)
                    limitTile(child, kind: .weekends, title: "Weekends", isToday: isWeekend)
                }
            } else {
                limitTile(child, kind: .everyDay, title: "Every day", isToday: true)

                Button {
                    splitLimits(for: child)
                } label: {
                    Label("Set a different weekend limit", systemImage: "calendar.badge.plus")
                        .font(.footnote.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.primary)
            }
        }
        .brightCard()
    }

    private func limitTile(_ child: ChildProfile, kind: LimitKind, title: String, isToday: Bool) -> some View {
        let minutes = limitValue(child, kind: kind)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                if isToday {
                    Text("· today")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.primary)

            HStack(spacing: 6) {
                Text(TimeText.compact(minutes))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 2)

                stepButton(systemImage: "minus", label: "Decrease \(title.lowercased()) limit") {
                    adjust(child, kind: kind, by: -15)
                }
                .disabled(minutes <= 15)

                stepButton(systemImage: "plus", label: "Increase \(title.lowercased()) limit") {
                    adjust(child, kind: kind, by: 15)
                }
                .disabled(minutes >= 1_440)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.primaryTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: minutes)
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 32, height: 32)
                .background(AppTheme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func limitValue(_ child: ChildProfile, kind: LimitKind) -> Int {
        switch kind {
        case .everyDay: child.dailyLimitMinutes
        case .weekdays: child.weekdayLimitMinutes ?? child.dailyLimitMinutes
        case .weekends: child.weekendLimitMinutes ?? child.dailyLimitMinutes
        }
    }

    /// Steps a limit by 15 minutes, staying inside the range the profile form allows.
    private func adjust(_ child: ChildProfile, kind: LimitKind, by delta: Int) {
        let newValue = min(max(limitValue(child, kind: kind) + delta, 15), 1_440)
        guard ChildProfile.isValidDailyLimit(newValue) else { return }

        withAnimation(AppTheme.motion(reduceMotion: reduceMotion)) {
            switch kind {
            case .everyDay: child.dailyLimitMinutes = newValue
            case .weekdays: child.weekdayLimitMinutes = newValue
            case .weekends: child.weekendLimitMinutes = newValue
            }
            child.updatedAt = .now
        }
        try? modelContext.save()
    }

    private func splitLimits(for child: ChildProfile) {
        withAnimation(AppTheme.motion(reduceMotion: reduceMotion)) {
            child.weekdayLimitMinutes = child.dailyLimitMinutes
            child.weekendLimitMinutes = child.dailyLimitMinutes
            child.updatedAt = .now
        }
        try? modelContext.save()
    }

    // MARK: - Week / month

    private func periodCard(_ child: ChildProfile) -> some View {
        let analysis = AnalysisCalculator.analyze(
            period: period,
            now: .now,
            childIDs: [child.id],
            sessions: sessions,
            devices: devicesAvailable(to: child)
        )
        let calendar = Calendar.current

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(period == .week ? "This week" : "This month")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                Spacer()
                Picker("Period", selection: $period.animation(AppTheme.motion(reduceMotion: reduceMotion))) {
                    ForEach(AnalysisPeriod.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            HStack(spacing: 8) {
                StatTile(
                    label: "Total",
                    value: TimeText.compact(analysis.currentMinutes),
                    detail: TimeText.change(analysis.changePercent) ?? "No earlier data",
                    detailColor: TimeText.changeColor(analysis.changePercent)
                )
                StatTile(
                    label: "Daily avg",
                    value: TimeText.compact(analysis.dailyAverageMinutes),
                    detail: "limit \(TimeText.compact(child.limitMinutes(on: .now)))"
                )
            }

            if analysis.dailyPoints.allSatisfy({ $0.minutes == 0 }) {
                Text("No usage recorded \(period == .week ? "this week" : "this month") yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Chart {
                    ForEach(analysis.dailyPoints) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Minutes", point.minutes)
                        )
                        .foregroundStyle(barColor(minutes: point.minutes, limit: child.limitMinutes(on: point.date), isToday: calendar.isDateInToday(point.date), childColor: child.color.color))
                        .cornerRadius(period == .week ? 6 : 2)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { _ in
                        AxisValueLabel(
                            format: period == .week
                                ? Date.FormatStyle.dateTime.weekday(.narrow)
                                : Date.FormatStyle.dateTime.day(),
                            centered: period == .week
                        )
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
            }
        }
        .brightCard()
    }

    private func barColor(minutes: Int, limit: Int, isToday: Bool, childColor: Color) -> Color {
        guard limit > 0 else { return childColor }
        switch DailyUsageSummary(usedMinutes: minutes, limitMinutes: limit).status {
        case .exceeded: return AppTheme.danger
        case .nearLimit, .reached: return AppTheme.warning
        case .normal: return isToday ? childColor : childColor.opacity(0.45)
        }
    }

    // MARK: - Devices

    private func devicesAvailable(to child: ChildProfile) -> [Device] {
        devices
            .filter { $0.isActive && $0.isAvailable(to: child.id) }
            .sorted { lhs, rhs in
                if lhs.isShared != rhs.isShared { return !lhs.isShared }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func devicesCard(_ child: ChildProfile) -> some View {
        let childDevices = devicesAvailable(to: child)

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "\(child.name)'s devices", detail: "today")

            if childDevices.isEmpty {
                Text("No devices available for \(child.name) yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(childDevices) { device in
                    let color = AppTheme.color(forDeviceID: device.id)
                    let today = UsageAggregator.totalMinutes(on: .now, childID: child.id, deviceID: device.id, sessions: sessions)

                    HStack(spacing: 10) {
                        Image(systemName: device.kind.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(color)
                            .frame(width: 32, height: 32)
                            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryDeep)
                                .lineLimit(1)
                            Text(device.isShared ? "Shared" : device.kind.title)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Text(TimeText.compact(today))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppTheme.primaryDeep)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("child-device-analysis-\(child.id.uuidString)-\(device.id.uuidString)")
                }
            }
        }
        .brightCard()
    }
}
