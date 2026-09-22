import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]
    @Query private var allUsageSessions: [UsageSession]
    @Query private var allDevices: [Device]

    let parent: ParentProfile

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    welcomeCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    sectionLabel("Children")
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 2, trailing: 4))
                        .listRowBackground(Color.clear)

                    if activeChildren.isEmpty {
                        ContentUnavailableView(
                            "No Children Yet",
                            systemImage: "figure.2.and.child.holdinghands",
                            description: Text("Add a child profile and choose their daily screen-time limit.")
                        )

                        Button("Add first child", systemImage: "plus.circle.fill") {
                            isAddingChild = true
                        }
                        .accessibilityIdentifier("add-child-button")
                    } else {
                        ForEach(activeChildren) { child in
                            childRow(child)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button("Archive", systemImage: "archivebox") {
                                        childToArchive = child
                                    }
                                    .tint(AppTheme.warning)

                                    Button("Edit", systemImage: "pencil") {
                                        childToEdit = child
                                    }
                                    .tint(AppTheme.primary)
                                }
                        }
                    }
                }

                if !archivedChildren.isEmpty {
                    Section {
                        sectionLabel("Archived")
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 2, trailing: 4))
                            .listRowBackground(Color.clear)

                        ForEach(archivedChildren) { child in
                            HStack {
                                childRow(child)
                                Spacer()
                                Button("Restore") {
                                    restore(child)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .contentMargins(.bottom, 100, for: .scrollContent)
            .animation(.easeInOut(duration: 0.25), value: activeChildren.count)
            .animation(.easeInOut(duration: 0.25), value: archivedChildren.count)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) {
                ParentSettingsView(parent: parent)
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
                        devices: allDevices.filter { $0.isActive && $0.isAvailable(to: childForTimer.id) }
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
                    if let childToArchive {
                        archive(childToArchive)
                    }
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
    }

    /// A section-header-style label rendered as a normal (non-pinned) row, instead
    /// of a List `Section` title — which sticks to the top of the screen while its
    /// section scrolls past. Used so "Children"/"Archived" scroll away with their
    /// content instead of floating over it.
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .textCase(.uppercase)

                Spacer()

                headerActions
            }

            Text("Welcome, \(parent.name)")
                .font(.title2.bold())

            if activeChildren.isEmpty {
                Text("Let’s set up your family.")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("\(activeChildren.count) active child \(activeChildren.count == 1 ? "profile" : "profiles")")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// Add-child and settings actions, shown inline at the top of the scrollable
    /// dashboard content (inside `welcomeCard`) rather than pinned in the nav bar —
    /// so they scroll away with the page and are only visible at the very top,
    /// instead of floating over content while scrolled down.
    private var headerActions: some View {
        HStack(spacing: 18) {
            Button {
                isAddingChild = true
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .foregroundStyle(AppTheme.primary)
            .accessibilityLabel("Add child")

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Settings")
        }
        .buttonStyle(.plain)
        .font(.system(size: 19, weight: .semibold))
    }

    private func childRow(_ child: ChildProfile) -> some View {
        let summary = UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)
        let statusColor = AppTheme.statusColor(for: summary.status)
        let devices = deviceBreakdown(for: child)
        let activeTimer = timerManager.timer(for: child.id)

        return TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    NavigationLink {
                        ChildDetailView(child: child)
                    } label: {
                        HStack(spacing: 12) {
                            ChildAvatarView(child: child, size: 44)
                            Text(child.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .accessibilityHint(child.isActive ? "Opens this child's devices" : "Opens archived child profile")

                    Spacer(minLength: 8)

                    if let activeTimer {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(remainingTime(until: activeTimer.endsAt, now: timeline.date))
                                .font(.title3.bold().monospacedDigit())

                            Button("Stop timer", systemImage: "stop.circle") {
                                timerManager.stop(
                                    activeTimer,
                                    now: timeline.date,
                                    children: allChildren,
                                    devices: allDevices,
                                    context: modelContext
                                )
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.danger)
                            .accessibilityIdentifier("stop-timer-\(child.id.uuidString)")
                        }
                    } else if child.isActive {
                        Button("Start timer", systemImage: "play.fill") {
                            childForTimer = child
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeDevices(for: child).isEmpty)
                        .accessibilityIdentifier("start-timer-\(child.id.uuidString)")
                    }
                }

                HStack(spacing: 12) {
                    ZStack {
                        RingProgressView(progress: summary.progress, color: statusColor, size: 48, lineWidth: 5)
                        Text(summary.overMinutes > 0 ? "+\(summary.overMinutes)" : "\(Int((summary.progress * 100).rounded()))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Daily screen-time progress")
                    .accessibilityValue("\(summary.usedMinutes) of \(summary.limitMinutes) minutes")

                    VStack(alignment: .leading, spacing: 2) {
                        (Text("\(summary.usedMinutes)").font(.title3.bold())
                            + Text(" of \(summary.limitMinutes) min").font(.caption).foregroundStyle(AppTheme.textSecondary))
                            .accessibilityIdentifier("today-used-total-\(child.id.uuidString)")

                        Text(summary.headline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }

                    Spacer()

                    Text(summary.remainingHeadline)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("today-limit-balance-\(child.id.uuidString)")
                }

                if !devices.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(devices.prefix(3), id: \.device.id) { entry in
                            DeviceUsageChip(
                                name: entry.device.name,
                                minutes: entry.minutes,
                                color: AppTheme.color(forDeviceID: entry.device.id)
                            )
                        }
                    }
                } else if child.isActive && activeDevices(for: child).isEmpty {
                    Text("Add a device to start tracking.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(18)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }

    private func deviceBreakdown(for child: ChildProfile) -> [(device: Device, minutes: Int)] {
        activeDevices(for: child)
            .map { device in
                (
                    device: device,
                    minutes: UsageAggregator.totalMinutes(
                        on: .now,
                        childID: child.id,
                        deviceID: device.id,
                        sessions: allUsageSessions
                    )
                )
            }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
    }

    private func activeDevices(for child: ChildProfile) -> [Device] {
        allDevices.filter { $0.isActive && $0.isAvailable(to: child.id) }
    }

    private func remainingTime(until end: Date, now: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(now)), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func timerProgress(_ timer: ActiveScreenTimer, now: Date) -> Double {
        let total = timer.endsAt.timeIntervalSince(timer.startedAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(timer.startedAt) / total, 0), 1)
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

#Preview {
    ContentView(parent: ParentProfile(name: "Taylor"))
        .modelContainer(
            for: [ParentProfile.self, ChildProfile.self, Device.self, UsageSession.self],
            inMemory: true
        )
}
