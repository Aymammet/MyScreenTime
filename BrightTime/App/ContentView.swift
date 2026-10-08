import Charts
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    /// Family usage yesterday up to this same time of day, so the comparison is fair
    /// in the morning instead of pitting a few hours against a whole day.
    private var yesterdaySoFarMinutes: Int? {
        let calendar = Calendar.current
        guard !activeChildren.isEmpty,
              let sameTimeYesterday = calendar.date(byAdding: .day, value: -1, to: .now) else { return nil }
        let activeIDs = Set(activeChildren.map(\.id))
        let start = calendar.startOfDay(for: sameTimeYesterday)
        let hadAnyUsage = allUsageSessions.contains { session in
            guard let childID = session.child?.id else { return false }
            return activeIDs.contains(childID) && calendar.isDate(session.startedAt, inSameDayAs: sameTimeYesterday)
        }
        guard hadAnyUsage else { return nil }
        return allUsageSessions
            .filter { session in
                guard let childID = session.child?.id else { return false }
                return activeIDs.contains(childID)
                    && session.startedAt >= start
                    && session.startedAt <= sameTimeYesterday
            }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                        .padding(.bottom, 4)

                    familyHero

                    hourlyCard

                    SectionLabel("Your children") {
                        if !activeChildren.isEmpty {
                            Button {
                                isAddingChild = true
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(AppTheme.primaryTint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add-child-button")
                        }
                    }
                    .padding(.top, 8)

                    if activeChildren.isEmpty {
                        emptyChildrenCard
                    } else {
                        ForEach(activeChildren) { child in
                            childCard(child)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }

                    if !archivedChildren.isEmpty {
                        archivedSection
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(AppTheme.motion(reduceMotion: reduceMotion), value: activeChildren.map(\.id))
                .animation(AppTheme.motion(reduceMotion: reduceMotion), value: archivedChildren.map(\.id))
            }
            .background(AppTheme.background.ignoresSafeArea())
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
        .sensoryFeedback(.impact(weight: .medium), trigger: timerManager.timers.map(\.id))
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(greeting)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            Button {
                isShowingSettings = true
            } label: {
                ParentAvatarView(parent: parent, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let partOfDay = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let firstName = parent.name.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? partOfDay : "\(partOfDay), \(firstName)"
    }

    // MARK: - Family hero

    private var familyHero: some View {
        let progress = familyLimitMinutes > 0 ? Double(familyUsedMinutes) / Double(familyLimitMinutes) : 0
        let percentText = familyLimitMinutes > 0 ? "\(Int((progress * 100).rounded()))%" : "—"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Family today")
                        .font(.footnote.weight(.semibold))
                        .opacity(0.85)
                    Text(TimeText.compact(familyUsedMinutes))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(heroSubtitle)
                        .font(.footnote.weight(.semibold))
                        .opacity(0.85)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                SunRingView(
                    progress: progress,
                    color: AppTheme.cream,
                    trackColor: Color.white.opacity(0.22),
                    rayColor: Color.white.opacity(0.5),
                    size: 108,
                    lineWidth: 9
                ) {
                    Text(percentText)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 6) {
                heroChip(comparisonText, systemImage: comparisonIcon)
                if !timerManager.timers.isEmpty {
                    let count = timerManager.timers.count
                    heroChip("\(count) timer\(count == 1 ? "" : "s") running", systemImage: "timer")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 100))
                .frame(width: 200, height: 200)
                .offset(x: 50, y: -70)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.primary.opacity(0.35), radius: 16, y: 10)
        .animation(AppTheme.motion(reduceMotion: reduceMotion), value: familyUsedMinutes)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Family screen time today")
        .accessibilityValue("\(TimeText.compact(familyUsedMinutes)) used. \(heroSubtitle). \(comparisonText)")
    }

    private var heroSubtitle: String {
        guard familyLimitMinutes > 0 else { return "No daily limits set yet" }
        let limit = TimeText.compact(familyLimitMinutes)
        if familyUsedMinutes > familyLimitMinutes {
            return "of \(limit) · \(TimeText.compact(familyUsedMinutes - familyLimitMinutes)) over"
        }
        return "of \(limit) · \(TimeText.compact(familyLimitMinutes - familyUsedMinutes)) left"
    }

    private var comparisonText: String {
        guard let yesterday = yesterdaySoFarMinutes else { return "No data from yesterday" }
        let difference = familyUsedMinutes - yesterday
        if difference == 0 { return "Same as this time yesterday" }
        return "\(TimeText.compact(abs(difference))) \(difference < 0 ? "less" : "more") than yesterday"
    }

    private var comparisonIcon: String {
        guard let yesterday = yesterdaySoFarMinutes else { return "clock" }
        if familyUsedMinutes == yesterday { return "equal" }
        return familyUsedMinutes < yesterday ? "arrow.down" : "arrow.up"
    }

    private func heroChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    // MARK: - Today by hour

    private var hourlyCard: some View {
        let usage = hourlyUsage
        let peak = usage.max { $0.minutes < $1.minutes }
        let hasUsage = (peak?.minutes ?? 0) > 0

        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(
                title: "Today by hour",
                detail: hasUsage ? peak.map { "Peak \(hourName($0.hour))" } : nil
            )

            if hasUsage {
                Chart(usage) { point in
                    BarMark(
                        x: .value("Hour", point.hour),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(point.hour == peak?.hour ? AppTheme.primary : AppTheme.primarySoft)
                    .cornerRadius(3)
                }
                .chartXScale(domain: -1...24)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(hourName(hour))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 72)
                .accessibilityLabel("Screen time by hour today")
            } else {
                Text("No screen time logged yet today.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .brightCard()
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

    private func hourName(_ hour: Int) -> String {
        guard let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) else {
            return "\(hour)"
        }
        return date.formatted(.dateTime.hour())
    }

    // MARK: - Children

    private var emptyChildrenCard: some View {
        VStack(spacing: 12) {
            SunRingView(progress: 0, color: AppTheme.primary, size: 72, lineWidth: 6) {
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }
            Text("No children yet")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            Text("Add a child profile to start tracking healthy screen-time habits.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add first child", systemImage: "plus.circle.fill") {
                isAddingChild = true
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier("add-child-button")
        }
        .frame(maxWidth: .infinity)
        .brightCard(padding: 24)
    }

    private func childCard(_ child: ChildProfile) -> some View {
        let summary = UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)
        let devices = activeDevices(for: child)
        let activeTimer = timerManager.timer(for: child.id)

        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                ChildDetailView(child: child)
            } label: {
                HStack(spacing: 12) {
                    ChildAvatarView(child: child, size: 48)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text(child.name)
                                .font(.headline)
                                .foregroundStyle(AppTheme.primaryDeep)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.textTertiary)
                            Spacer(minLength: 4)
                            BrightChip.status(balanceText(for: summary), summary.status)
                                .accessibilityIdentifier("today-limit-balance-\(child.id.uuidString)")
                        }

                        LimitBar(progress: summary.progress, color: AppTheme.statusColor(for: summary.status))

                        Text(usageLine(for: child, summary: summary))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .accessibilityIdentifier("today-used-total-\(child.id.uuidString)")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(AppTheme.cardBorder)
                .frame(height: 1)

            timerRow(for: child, activeTimer: activeTimer, devices: devices)
        }
        .brightCard(padding: 14)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { childToEdit = child }
            Button("Archive", systemImage: "archivebox", role: .destructive) { childToArchive = child }
        }
        .sensoryFeedback(trigger: summary.status) { _, newStatus in
            newStatus == .normal ? nil : .warning
        }
    }

    @ViewBuilder
    private func timerRow(for child: ChildProfile, activeTimer: ActiveScreenTimer?, devices: [Device]) -> some View {
        if let activeTimer {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.primary)
                    .frame(width: 8, height: 8)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text("\(activeTimer.deviceName) · \(remainingTime(until: activeTimer.endsAt, now: timeline.date))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.primary)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                }

                Spacer(minLength: 8)

                Button {
                    timerManager.stop(
                        activeTimer,
                        now: .now,
                        children: allChildren,
                        devices: allDevices,
                        context: modelContext
                    )
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop timer")
                .accessibilityIdentifier("stop-timer-\(child.id.uuidString)")
            }
        } else {
            let readyText: String = devices.isEmpty
                ? "Add a device to use timers"
                : "\(devices.count) " + (devices.count == 1 ? "device ready" : "devices ready")

            HStack(spacing: 8) {
                Text(readyText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer(minLength: 8)

                Button {
                    childForTimer = child
                } label: {
                    Label("Start timer", systemImage: "timer")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.primaryTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(devices.isEmpty)
                .opacity(devices.isEmpty ? 0.45 : 1)
                .accessibilityIdentifier("start-timer-\(child.id.uuidString)")
            }
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archived")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            ForEach(archivedChildren) { child in
                HStack(spacing: 12) {
                    ChildAvatarView(child: child, size: 36)
                        .saturation(0.3)
                    Text(child.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Button("Restore") { restore(child) }
                        .font(.subheadline.bold())
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
                .brightCard(padding: 12)
            }
        }
    }

    // MARK: - Helpers

    private func balanceText(for summary: DailyUsageSummary) -> String {
        if summary.overMinutes > 0 { return "\(TimeText.compact(summary.overMinutes)) over" }
        if summary.status == .reached { return "Limit reached" }
        return "\(TimeText.compact(summary.remainingMinutes)) left"
    }

    private func usageLine(for child: ChildProfile, summary: DailyUsageSummary) -> String {
        let base = "\(TimeText.compact(summary.usedMinutes)) of \(TimeText.compact(summary.limitMinutes))"
        let names = devicesUsedToday(by: child)
        return names.isEmpty ? "\(base) today" : "\(base) · \(names.joined(separator: ", "))"
    }

    private func devicesUsedToday(by child: ChildProfile) -> [String] {
        let calendar = Calendar.current
        var seen = Set<UUID>()
        var names: [String] = []
        for session in allUsageSessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard session.child?.id == child.id,
                  calendar.isDateInToday(session.startedAt),
                  let device = session.device,
                  !seen.contains(device.id) else { continue }
            seen.insert(device.id)
            names.append(device.name)
        }
        return names
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
