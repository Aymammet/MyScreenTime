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

                Section("Children") {
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

                        Button("Add child", systemImage: "plus") {
                            isAddingChild = true
                        }
                        .accessibilityIdentifier("add-child-button")
                    }
                }

                if !archivedChildren.isEmpty {
                    Section("Archived") {
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
            .navigationTitle("MyScreenTime")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Add child", systemImage: "plus") {
                        isAddingChild = true
                    }

                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
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

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome, \(parent.name)")
                .font(.title2.bold())

            if activeChildren.isEmpty {
                Text("Let’s set up your family.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(activeChildren.count) active child \(activeChildren.count == 1 ? "profile" : "profiles")")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func childRow(_ child: ChildProfile) -> some View {
        let summary = UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)
        let activeTimer = timerManager.timer(for: child.id)

        return VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            ChildDetailView(child: child)
                        } label: {
                            HStack(spacing: 12) {
                                ChildAvatarView(child: child, size: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(child.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let activeTimer {
                                        Text("\(activeTimer.deviceName) • running")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .accessibilityHint(child.isActive ? "Opens this child's devices" : "Opens archived child profile")

                        Spacer(minLength: 8)

                        if let activeTimer {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(remainingTime(until: activeTimer.endsAt, now: timeline.date))
                                    .font(.title2.bold().monospacedDigit())

                                Text("\(activeTimer.durationMinutes) min session")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button("Stop timer", systemImage: "stop.circle") {
                                    timerManager.stop(
                                        activeTimer,
                                        now: timeline.date,
                                        children: allChildren,
                                        devices: allDevices,
                                        context: modelContext
                                    )
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.danger)
                                .accessibilityIdentifier("stop-timer-\(child.id.uuidString)")
                            }
                        } else if child.isActive {
                            Button("Start timer", systemImage: "play.fill") {
                                childForTimer = child
                            }
                            .buttonStyle(.bordered)
                            .disabled(activeDevices(for: child).isEmpty)
                            .accessibilityIdentifier("start-timer-\(child.id.uuidString)")
                        }
                    }

                    dailyUsageFooter(summary)
                }
            }
        }
    }

    private func dailyUsageFooter(_ summary: DailyUsageSummary) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text("\(UsageAggregator.format(minutes: summary.usedMinutes)) used")
                    .foregroundStyle(.secondary)

                Spacer()

                Text(remainingLabel(for: summary))
                    .foregroundStyle(summary.overMinutes > 0 ? AppTheme.danger : AppTheme.primary)
            }
            .font(.caption.weight(.medium))

            ProgressView(value: summary.progress)
                .tint(summary.overMinutes > 0 ? AppTheme.danger : AppTheme.primary)
                .accessibilityLabel("Daily screen-time progress")
                .accessibilityValue("\(summary.usedMinutes) of \(summary.limitMinutes) minutes")

            Text("\(UsageAggregator.format(minutes: summary.limitMinutes)) daily limit")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func remainingLabel(for summary: DailyUsageSummary) -> String {
        if summary.overMinutes > 0 {
            return "\(UsageAggregator.format(minutes: summary.overMinutes)) over"
        }

        return "\(UsageAggregator.format(minutes: summary.remainingMinutes)) remaining"
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

    private func statusColor(for status: DailyLimitStatus) -> Color {
        switch status {
        case .normal: AppTheme.success
        case .nearLimit, .reached: AppTheme.warning
        case .exceeded: AppTheme.danger
        }
    }
}

#Preview {
    ContentView(parent: ParentProfile(name: "Taylor"))
        .modelContainer(
            for: [ParentProfile.self, ChildProfile.self, Device.self, UsageSession.self],
            inMemory: true
        )
}
