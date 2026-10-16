import Charts
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]
    @Query private var allUsageSessions: [UsageSession]
    @Query private var allDevices: [Device]
    @Query(sort: \TimeRequest.createdAt) private var allRequests: [TimeRequest]

    let parent: ParentProfile

    @State private var isAddingChild = false
    /// The usage day Home was last drawn for. Bumped by the minute check below so
    /// the cards roll over to a new day (midnight, or the parent's reset hour).
    @State private var usageDay = AppCalendar.day.startOfDay(for: .now)
    @State private var childToEdit: ChildProfile?
    @State private var childToArchive: ChildProfile?
    @State private var childForTimer: ChildProfile?
    @EnvironmentObject private var timerManager: ScreenTimerManager

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
        let calendar = AppCalendar.day
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
        let _ = calendarRevision
        let _ = usageDay
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                        .padding(.bottom, 4)

                    TimeZoneNotice()

                    PasscodeAlertsCard()

                    PendingRequestsCard()

                    familyHero

                    hourlyCard

                    SectionLabel("Your kids") {
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

                    DailyInsightsCard()
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, AppTheme.tabBarContentClearance)
                .animation(AppTheme.motion(reduceMotion: reduceMotion), value: activeChildren.map(\.id))
                .animation(AppTheme.motion(reduceMotion: reduceMotion), value: archivedChildren.map(\.id))
                .scrollTopAnchor()
            }
            .scrollsToTopOnTabReselect()
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("BrightTime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
                        devices: activeDevices(for: childForTimer),
                        todaySummary: UsageAggregator.summary(
                            on: .now,
                            child: childForTimer,
                            sessions: allUsageSessions
                        )
                    ) { device, minutes, notifyWhenFinished, showOnLockScreen in
                        timerManager.start(
                            child: childForTimer,
                            device: device,
                            minutes: minutes,
                            notifyWhenFinished: notifyWhenFinished,
                            showOnLockScreen: showOnLockScreen
                        )
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
                "Archive this kid?",
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                refreshUsageDay()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshUsageDay() }
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
        // Redraws every minute so the greeting, date and status line stay correct
        // while the app sits open (past 5 PM, past midnight, as timers end).
        TimelineView(.everyMinute) { context in
            let now = context.date
            let partOfDay = HomeGreeting.PartOfDay(hour: AppCalendar.display.component(.hour, from: now))
            let status = homeStatus(now: now, partOfDay: partOfDay)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: partOfDay.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(partOfDay.tint)
                        .accessibilityHidden(true)
                    Text(now.formatted(headerDateStyle))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

                Text(greeting(partOfDay))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(status.tone.dotColor)
                        .frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 4 }
                        .accessibilityHidden(true)
                    Text(status.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(status.tone.textColor)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
                .padding(.top, 4)
                .animation(AppTheme.motion(reduceMotion: reduceMotion), value: status.text)
                .accessibilityIdentifier("home-status-line")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerDateStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()
        style.timeZone = AppCalendar.display.timeZone
        return style
    }

    private func greeting(_ partOfDay: HomeGreeting.PartOfDay) -> String {
        let firstName = HomeGreeting.firstName(parent.name)
        return firstName.isEmpty ? partOfDay.greeting : "\(partOfDay.greeting), \(firstName)"
    }

    private func homeStatus(now: Date, partOfDay: HomeGreeting.PartOfDay) -> HomeGreeting.Status {
        let kids = activeChildren
        let names = Dictionary(uniqueKeysWithValues: kids.map { ($0.id, HomeGreeting.firstName($0.name)) })
        let dayCalendar = AppCalendar.day

        let requests = allRequests
            .filter { $0.status == .pending && dayCalendar.isDate($0.day, inSameDayAs: now) }
            .compactMap { request in names[request.childID].map { HomeGreeting.Request(name: $0, minutes: request.minutes) } }

        let timers = timerManager.timers
            .filter { names[$0.childID] != nil && $0.endsAt > now }
            .map { HomeGreeting.RunningTimer(name: names[$0.childID] ?? $0.childName, endsAt: $0.endsAt) }

        let usage = zip(kids, familySummaries).map { child, summary in
            HomeGreeting.KidUsage(name: names[child.id] ?? child.name, used: summary.usedMinutes, limit: summary.limitMinutes)
        }

        return HomeGreeting.status(
            now: now,
            partOfDay: partOfDay,
            hasKids: !kids.isEmpty,
            requests: requests,
            timers: timers,
            usage: usage
        )
    }

    private func refreshUsageDay() {
        let today = AppCalendar.day.startOfDay(for: .now)
        if today != usageDay { usageDay = today }
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
                    color: AppTheme.heroRing,
                    trackColor: AppTheme.heroRingTrack,
                    rayColor: AppTheme.heroRays,
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
        .foregroundStyle(AppTheme.heroText)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(RadialGradient(colors: [AppTheme.heroGlow, .clear], center: .center, startRadius: 0, endRadius: 100))
                .frame(width: 200, height: 200)
                .offset(x: 50, y: -70)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.heroBorder, lineWidth: 1)
        }
        .shadow(color: AppTheme.primary.opacity(0.3), radius: 16, y: 10)
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
            .background(AppTheme.heroChip, in: Capsule())
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
                        x: .value("Hour", point.slot),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(point.hour == peak?.hour ? AppTheme.primary : AppTheme.primarySoft)
                    .cornerRadius(3)
                }
                .chartXScale(domain: -1...24)
                .chartXAxis {
                    // Slots start at the day-reset hour, so 12–3 AM sits at the
                    // end of the evening it belongs to, not the start of the chart.
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisValueLabel {
                            if let slot = value.as(Int.self) {
                                Text(hourName((slot + AppCalendar.dayResetHour) % 24))
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
        let dayCalendar = AppCalendar.day
        let clock = AppCalendar.display
        let activeIDs = Set(activeChildren.map(\.id))
        var minutes = Array(repeating: 0, count: 24)

        for session in allUsageSessions {
            guard let childID = session.child?.id,
                  activeIDs.contains(childID),
                  dayCalendar.isDateInToday(session.startedAt) else { continue }
            minutes[clock.component(.hour, from: session.startedAt)] += session.durationMinutes
        }

        let resetHour = AppCalendar.dayResetHour
        return minutes.enumerated().map {
            HourlyUsage(hour: $0.offset, slot: ($0.offset - resetHour + 24) % 24, minutes: $0.element)
        }
    }

    private func hourName(_ hour: Int) -> String {
        guard let date = AppCalendar.display.date(bySettingHour: hour, minute: 0, second: 0, of: .now) else {
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
            Text("No kids yet")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            Text("Add a kid profile to start tracking healthy screen-time habits.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add first kid", systemImage: "plus.circle.fill") {
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
                    .popsToRootOnTabReselect()
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
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.danger)
                        .frame(width: 8, height: 8)

                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("\(activeTimer.deviceName) · \(remainingTime(until: activeTimer.endsAt, now: timeline.date))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppTheme.dangerText)
                            .lineLimit(1)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, isDimmed in
                    content.opacity(isDimmed ? 0.35 : 1)
                } animation: { _ in
                    .easeInOut(duration: 0.65)
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
                        .foregroundStyle(AppTheme.onDanger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.danger, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop timer")
                .accessibilityIdentifier("stop-timer-\(child.id.uuidString)")
            }
        } else {
            let deviceText: String = devices.isEmpty
                ? "Add a device to use timers"
                : "\(devices.count) " + (devices.count == 1 ? "device ready" : "devices ready")
            let bank = child.bankBalance
            let readyText = bank > 0 && !devices.isEmpty ? "\(deviceText) · \(TimeText.compact(bank)) banked" : deviceText

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
        let calendar = AppCalendar.day
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
        // Record and stop a running timer first; once archived, its card (and
        // Stop button) disappear.
        timerManager.stopTimer(
            forChildID: child.id,
            children: allChildren,
            devices: allDevices,
            context: modelContext
        )
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
    /// Position on the chart, counted from the day-reset hour.
    let slot: Int
    let minutes: Int
    var id: Int { hour }
}

#Preview {
    ContentView(parent: ParentProfile(name: "Taylor"))
        .environmentObject(ScreenTimerManager())
        .environment(AppLock())
        .modelContainer(
            for: [ParentProfile.self, ChildProfile.self, Device.self, UsageSession.self, EarnActivity.self, TimeCredit.self],
            inMemory: true
        )
}

// MARK: - Home greeting

/// The Home title and the one-line status under it. Pure logic, so it is easy to test.
enum HomeGreeting {
    enum PartOfDay: Equatable {
        case morning, afternoon, evening, night

        /// 5 AM–noon morning, noon–5 PM afternoon, 5–10 PM evening, 10 PM–5 AM night.
        init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<22: self = .evening
            default: self = .night
            }
        }

        var greeting: String {
            switch self {
            case .morning: "Good morning"
            case .afternoon: "Good afternoon"
            case .evening: "Good evening"
            case .night: "Good night"
            }
        }

        var symbol: String {
            switch self {
            case .morning: "sunrise.fill"
            case .afternoon: "sun.max.fill"
            case .evening: "sunset.fill"
            case .night: "moon.stars.fill"
            }
        }

        var tint: Color {
            switch self {
            case .morning, .afternoon: Color(red: 0.95, green: 0.72, blue: 0.25)
            case .evening: Color(red: 0.93, green: 0.55, blue: 0.36)
            case .night: Color(red: 0.55, green: 0.66, blue: 0.93)
            }
        }
    }

    enum Tone: Equatable {
        case attention, info, calm

        var dotColor: Color {
            switch self {
            case .attention: AppTheme.warning
            case .info: AppTheme.primary
            case .calm: AppTheme.textSecondary.opacity(0.6)
            }
        }

        var textColor: Color {
            self == .attention ? AppTheme.warningText : AppTheme.textSecondary
        }
    }

    struct Status: Equatable {
        let text: String
        let tone: Tone
    }

    struct Request { let name: String; let minutes: Int }
    struct RunningTimer { let name: String; let endsAt: Date }
    struct KidUsage { let name: String; let used: Int; let limit: Int }

    static func firstName(_ fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? ""
    }

    /// Picks the single most important thing for the parent right now.
    static func status(
        now: Date,
        partOfDay: PartOfDay,
        hasKids: Bool,
        requests: [Request],
        timers: [RunningTimer],
        usage: [KidUsage]
    ) -> Status {
        guard hasKids else {
            return Status(text: "Add a kid to start tracking screen time", tone: .calm)
        }

        // 1. A kid is waiting for an answer.
        if let first = requests.first {
            let text = requests.count == 1
                ? "\(first.name) is asking for \(TimeText.spoken(first.minutes)) more"
                : "\(requests.count) requests for more time"
            return Status(text: text, tone: .attention)
        }

        // 2. Screens still on late at night.
        if partOfDay == .night, let first = timers.first {
            let text = timers.count == 1
                ? "\(first.name)'s timer is still running late at night"
                : "\(timers.count) timers still running late at night"
            return Status(text: text, tone: .attention)
        }

        // 3. Someone went over their limit.
        let over = usage.filter { $0.limit > 0 && $0.used > $0.limit }
        if let first = over.first {
            let text: String
            switch over.count {
            case 1: text = "\(first.name) is \(TimeText.compact(first.used - first.limit)) over today's limit"
            case 2: text = "\(over[0].name) and \(over[1].name) are over their limits"
            default: text = "\(over.count) kids are over their limits"
            }
            return Status(text: text, tone: .attention)
        }

        // 4. Timers running: say when the next one ends.
        if let next = timers.min(by: { $0.endsAt < $1.endsAt }) {
            let minutesLeft = max(Int((next.endsAt.timeIntervalSince(now) / 60).rounded(.up)), 1)
            let text = timers.count == 1
                ? "\(next.name)'s timer ends in \(TimeText.compact(minutesLeft))"
                : "\(timers.count) timers running · next ends in \(TimeText.compact(minutesLeft))"
            return Status(text: text, tone: .info)
        }

        // 5. Someone is close to their limit.
        let near = usage
            .filter { $0.limit > 0 && $0.used < $0.limit && $0.used * 100 >= $0.limit * 80 }
            .min { ($0.limit - $0.used) < ($1.limit - $1.used) }
        if let near {
            return Status(text: "\(near.name) has \(TimeText.compact(near.limit - near.used)) left today", tone: .info)
        }

        // 6. Nothing needs attention.
        let used = usage.reduce(0) { $0 + $1.used }
        let limit = usage.reduce(0) { $0 + $1.limit }
        if used == 0 {
            let text = limit > 0 ? "Fresh day · \(TimeText.compact(limit)) to share" : "No screen time yet today"
            return Status(text: text, tone: .calm)
        }
        guard limit > 0 else {
            return Status(text: "\(TimeText.compact(used)) of screen time so far today", tone: .calm)
        }
        if partOfDay == .evening || partOfDay == .night {
            return Status(text: "All quiet · everyone's within today's limits", tone: .calm)
        }
        return Status(text: "Everyone's within limits · \(TimeText.compact(limit - used)) left", tone: .calm)
    }
}
