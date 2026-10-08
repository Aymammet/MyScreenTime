import Charts
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]
    @Query private var allUsageSessions: [UsageSession]
    @Query private var allDevices: [Device]

    let parent: ParentProfile
    var onSignOut: () -> Void = {}

    @State private var isShowingSettings = false
    @State private var isAddingChild = false
    @State private var childToEdit: ChildProfile?
    @State private var childToArchive: ChildProfile?
    @State private var childForTimer: ChildProfile?
    @StateObject private var timerManager = ScreenTimerManager()

    private let childAccents: [Color] = [
        AppTheme.primary,
        AppTheme.rose,
        Color(red: 0.949, green: 0.553, blue: 0.294),
        AppTheme.lavender
    ]

    private var activeChildren: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id && $0.isActive }
    }

    private var archivedChildren: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id && !$0.isActive }
    }

    private var familySummaries: [DailyUsageSummary] {
        activeChildren.map { UsageAggregator.summary(on: .now, child: $0, sessions: allUsageSessions) }
    }

    private var familyUsedMinutes: Int {
        familySummaries.reduce(0) { $0 + $1.usedMinutes }
    }

    private var familyLimitMinutes: Int {
        familySummaries.reduce(0) { $0 + $1.limitMinutes }
    }

    private var familyAverageMinutes: Int {
        guard !activeChildren.isEmpty else { return 0 }
        return familyUsedMinutes / activeChildren.count
    }

    private var familyRemainingMinutes: Int {
        max(familyLimitMinutes - familyUsedMinutes, 0)
    }

    private var yesterdayAverageMinutes: Int {
        guard !activeChildren.isEmpty,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) else { return 0 }
        let total = activeChildren.reduce(0) { result, child in
            result + UsageAggregator.totalMinutes(
                on: yesterday,
                childID: child.id,
                sessions: allUsageSessions
            )
        }
        return total / activeChildren.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    brandHeader
                    dailySnapshot
                    childrenHeader

                    if activeChildren.isEmpty {
                        emptyChildrenCard
                    } else {
                        ForEach(Array(activeChildren.enumerated()), id: \.element.id) { index, child in
                            childCard(child, accent: childAccents[index % childAccents.count])

                            if index < activeChildren.count - 1 {
                                childSeparator
                            }
                        }
                    }

                    if !archivedChildren.isEmpty {
                        archivedSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .contentMargins(.bottom, 84, for: .scrollContent)
            .navigationTitle("BrightTime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) {
                ParentSettingsView(parent: parent, onSignOut: onSignOut)
            }
            .sheet(isPresented: $isAddingChild) {
                ChildFormView(parent: parent)
            }
            .sheet(
                isPresented: Binding(
                    get: { childForTimer != nil },
                    set: { if !$0 { childForTimer = nil } }
                )
            ) {
                if let childForTimer {
                    StartTimerView(
                        child: childForTimer,
                        devices: activeDevices(for: childForTimer)
                    ) { device, minutes in
                        timerManager.start(child: childForTimer, device: device, minutes: minutes)
                    }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { childToEdit != nil },
                    set: { if !$0 { childToEdit = nil } }
                )
            ) {
                if let childToEdit {
                    ChildFormView(parent: parent, child: childToEdit)
                }
            }
            .confirmationDialog(
                "Archive this child?",
                isPresented: Binding(
                    get: { childToArchive != nil },
                    set: { if !$0 { childToArchive = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Archive", role: .destructive) {
                    if let childToArchive { archive(childToArchive) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their history will be kept, and you can restore the profile later.")
            }
        }
        .tint(AppTheme.primary)
        .overlay {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Color.clear
                    .onChange(of: timeline.date) { _, now in
                        timerManager.completeDueTimers(
                            now: now,
                            children: allChildren,
                            devices: allDevices,
                            context: modelContext
                        )
                    }
            }
            .allowsHitTesting(false)
        }
#if DEBUG
        .task(id: sampleDataSeedID) {
            guard !CommandLine.arguments.contains("-ui-testing") else { return }
            _ = try? SampleUsageSeeder.seedPreviousWeekIfNeeded(
                children: activeChildren,
                devices: allDevices,
                existingSessions: allUsageSessions,
                context: modelContext
            )
        }
#endif
    }

#if DEBUG
    private var sampleDataSeedID: String {
        let childIDs = activeChildren.map(\.id.uuidString).sorted().joined(separator: ",")
        let deviceIDs = allDevices.filter(\.isActive).map(\.id.uuidString).sorted().joined(separator: ",")
        return "\(childIDs)|\(deviceIDs)"
    }
#endif

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.969, blue: 0.996),
                Color(red: 0.985, green: 0.982, blue: 1.000),
                AppTheme.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.primary, AppTheme.lavender],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("BrightTime")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.primary, AppTheme.lavender],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                ParentAvatarView(parent: parent, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var dailySnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily snapshot")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.primaryDeep)

                Spacer()

                Label("Today", systemImage: "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.72), in: Capsule())
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compactDuration(familyAverageMinutes))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text("family average today")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                snapshotMetric(
                    icon: "clock",
                    value: compactDuration(familyRemainingMinutes),
                    label: familyUsedMinutes > familyLimitMinutes ? "over limit" : "left"
                )

                snapshotMetric(
                    icon: comparisonIcon,
                    value: comparisonValue,
                    label: comparisonLabel
                )
            }

            Chart(hourlyUsage) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.primary.opacity(0.38), AppTheme.primary],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3]))
                        .foregroundStyle(AppTheme.cardBorder)
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hourLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 92)
            .padding(12)
            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.primaryTint, Color.white.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: AppTheme.primary.opacity(0.12), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func snapshotMetric(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 78)
        .padding(.vertical, 12)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var childrenHeader: some View {
        HStack {
            Text("Your children")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.primaryDeep)

            Spacer()

            Button {
                isAddingChild = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(AppTheme.primaryTint, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-child-button")
        }
    }

    private var emptyChildrenCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.2.and.child.holdinghands")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.primary)
            Text("No children yet")
                .font(.headline)
            Text("Add a child profile to start tracking healthy screen-time habits.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add first child", systemImage: "plus.circle.fill") {
                isAddingChild = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("add-child-button")
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.primaryDeep.opacity(0.06), radius: 12, y: 5)
    }

    private var childSeparator: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [AppTheme.primary.opacity(0.08), AppTheme.lavender.opacity(0.25), AppTheme.primary.opacity(0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 5)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    private func childCard(_ child: ChildProfile, accent: Color) -> some View {
        let summary = UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)
        let devices = activeDevices(for: child)
        let activeTimer = timerManager.timer(for: child.id)

        return TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 14) {
                    NavigationLink {
                        ChildDetailView(child: child)
                    } label: {
                        HStack(spacing: 14) {
                            ChildAvatarView(child: child, size: 66)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(child.name)
                                        .font(.title3.bold())
                                        .foregroundStyle(AppTheme.primaryDeep)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.textTertiary)
                                }

                                Text(compactDuration(summary.usedMinutes))
                                    .font(.title2.bold())
                                    .foregroundStyle(AppTheme.primaryDeep)
                                    .accessibilityIdentifier("today-used-total-\(child.id.uuidString)")
                                Text("today’s total")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    ZStack {
                        RingProgressView(
                            progress: summary.progress,
                            color: summary.status == .normal ? accent : AppTheme.statusColor(for: summary.status),
                            trackColor: accent.opacity(0.13),
                            size: 72,
                            lineWidth: 8
                        )
                        VStack(spacing: 0) {
                            Text(summary.overMinutes > 0 ? "+\(summary.overMinutes)" : "\(Int((summary.progress * 100).rounded()))%")
                                .font(.headline.bold())
                            Text(summary.overMinutes > 0 ? "over" : "used")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .foregroundStyle(AppTheme.primaryDeep)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Daily screen-time progress")
                    .accessibilityValue("\(summary.usedMinutes) of \(summary.limitMinutes) minutes")
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(limitLine(for: summary))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .accessibilityIdentifier("today-limit-balance-\(child.id.uuidString)")

                    ProgressView(value: min(summary.progress, 1))
                        .tint(summary.status == .normal ? accent : AppTheme.statusColor(for: summary.status))
                        .scaleEffect(x: 1, y: 1.8, anchor: .center)
                }
                .padding(13)
                .background(accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Group {
                    if let activeTimer {
                        HStack {
                            Label(
                                remainingTime(until: activeTimer.endsAt, now: timeline.date),
                                systemImage: "timer"
                            )
                            .font(.headline.bold().monospacedDigit())

                            Spacer()

                            Button("Stop timer", systemImage: "stop.fill") {
                                timerManager.stop(
                                    activeTimer,
                                    now: timeline.date,
                                    children: allChildren,
                                    devices: allDevices,
                                    context: modelContext
                                )
                            }
                            .font(.subheadline.bold())
                            .accessibilityIdentifier("stop-timer-\(child.id.uuidString)")
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(AppTheme.danger, in: Capsule())
                    } else {
                        Button {
                            childForTimer = child
                        } label: {
                            Label("Start timer", systemImage: "timer")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    LinearGradient(
                                        colors: [accent, accent.opacity(0.78)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(devices.isEmpty)
                        .opacity(devices.isEmpty ? 0.45 : 1)
                        .accessibilityIdentifier("start-timer-\(child.id.uuidString)")
                    }
                }
            }
            .padding(17)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accent.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: AppTheme.primaryDeep.opacity(0.075), radius: 14, y: 6)
            .contextMenu {
                Button("Edit", systemImage: "pencil") { childToEdit = child }
                Button("Archive", systemImage: "archivebox", role: .destructive) { childToArchive = child }
            }
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archived")
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(archivedChildren) { child in
                HStack {
                    ChildAvatarView(child: child, size: 38)
                    Text(child.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Restore") { restore(child) }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var comparisonValue: String {
        guard yesterdayAverageMinutes > 0 else { return "—" }
        let percent = Int((abs(Double(familyAverageMinutes - yesterdayAverageMinutes)) / Double(yesterdayAverageMinutes) * 100).rounded())
        return "\(percent)%"
    }

    private var comparisonLabel: String {
        guard yesterdayAverageMinutes > 0 else { return "no prior data" }
        if familyAverageMinutes == yesterdayAverageMinutes { return "same as yesterday" }
        return familyAverageMinutes < yesterdayAverageMinutes ? "less than yesterday" : "more than yesterday"
    }

    private var comparisonIcon: String {
        guard yesterdayAverageMinutes > 0 else { return "chart.bar" }
        if familyAverageMinutes == yesterdayAverageMinutes { return "equal.circle" }
        return familyAverageMinutes < yesterdayAverageMinutes ? "arrow.down.right" : "arrow.up.right"
    }

    private var hourlyUsage: [HourlyUsage] {
        let calendar = Calendar.current
        let activeIDs = Set(activeChildren.map(\.id))
        var minutes = Array(repeating: 0, count: 24)

        for session in allUsageSessions {
            guard let childID = session.child?.id,
                  activeIDs.contains(childID),
                  calendar.isDateInToday(session.startedAt) else { continue }
            minutes[calendar.component(.hour, from: session.startedAt)] += session.durationMinutes
        }

        return minutes.enumerated().map { HourlyUsage(hour: $0.offset, minutes: $0.element) }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12 AM"
        case 6: "6 AM"
        case 12: "12 PM"
        case 18: "6 PM"
        case 23: "12 AM"
        default: ""
        }
    }

    private func compactDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private func limitLine(for summary: DailyUsageSummary) -> String {
        if summary.overMinutes > 0 {
            return "\(compactDuration(summary.overMinutes)) over / \(compactDuration(summary.limitMinutes)) limit"
        }
        return "\(compactDuration(summary.remainingMinutes)) remaining / \(compactDuration(summary.limitMinutes))"
    }

    private func activeDevices(for child: ChildProfile) -> [Device] {
        allDevices.filter { $0.isActive && $0.isAvailable(to: child.id) }
    }

    private func remainingTime(until end: Date, now: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(now)), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func archive(_ child: ChildProfile) {
        child.isActive = false
        child.updatedAt = .now
        try? modelContext.save()
        childToArchive = nil
    }

    private func restore(_ child: ChildProfile) {
        child.isActive = true
        child.updatedAt = .now
        try? modelContext.save()
    }
}

private struct HourlyUsage: Identifiable {
    let hour: Int
    let minutes: Int
    var id: Int { hour }
}

#Preview {
    ContentView(parent: ParentProfile(name: "Taylor"))
        .modelContainer(
            for: [ParentProfile.self, ChildProfile.self, Device.self, UsageSession.self],
            inMemory: true
        )
}
