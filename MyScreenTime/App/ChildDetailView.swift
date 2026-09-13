import SwiftData
import SwiftUI

struct ChildDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.createdAt) private var allDevices: [Device]
    @Query(sort: \UsageSession.startedAt, order: .reverse) private var allUsageSessions: [UsageSession]

    let child: ChildProfile

    @State private var isAddingDevice = false
    @State private var deviceToEdit: Device?
    @State private var deviceToArchive: Device?
    @State private var isAddingUsage = false
    @State private var sessionToEdit: UsageSession?
    @State private var sessionToDelete: UsageSession?

    private var activeDevices: [Device] {
        allDevices.filter { $0.child?.id == child.id && $0.isActive }
    }

    private var archivedDevices: [Device] {
        allDevices.filter { $0.child?.id == child.id && !$0.isActive }
    }

    private var recentUsageSessions: [UsageSession] {
        Array(allUsageSessions.filter { $0.child?.id == child.id }.prefix(10))
    }

    private var todaySummary: DailyUsageSummary {
        UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ChildAvatarView(child: child, size: 56)
                    Text(child.name).font(.title2.bold())
                }
            }
            Section("Today") {
                LabeledContent("Used", value: UsageAggregator.format(minutes: todaySummary.usedMinutes))
                    .accessibilityIdentifier("today-used-total")

                if todaySummary.overMinutes > 0 {
                    LabeledContent("Over limit", value: UsageAggregator.format(minutes: todaySummary.overMinutes))
                        .foregroundStyle(AppTheme.danger)
                        .accessibilityIdentifier("today-limit-balance")
                } else {
                    LabeledContent("Remaining", value: UsageAggregator.format(minutes: todaySummary.remainingMinutes))
                        .accessibilityIdentifier("today-limit-balance")
                }

                ProgressView(value: todaySummary.progress) {
                    Text("Today's limit: \(child.formattedLimit(on: .now))")
                }
                .tint(statusColor(for: todaySummary.status))
                .accessibilityValue("\(todaySummary.usedMinutes) of \(todaySummary.limitMinutes) minutes")
            }

            Section("Devices") {
                if activeDevices.isEmpty {
                    ContentUnavailableView(
                        "No Devices Yet",
                        systemImage: "display.2",
                        description: Text("Add the phones, computers, TVs, and other screens this child uses.")
                    )

                    Button("Add first device", systemImage: "plus.circle.fill") {
                        isAddingDevice = true
                    }
                    .accessibilityIdentifier("add-device-button")
                } else {
                    ForEach(activeDevices) { device in
                        deviceRow(device)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                deviceToEdit = device
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Archive", systemImage: "archivebox") {
                                    deviceToArchive = device
                                }
                                .tint(AppTheme.warning)

                                Button("Edit", systemImage: "pencil") {
                                    deviceToEdit = device
                                }
                                .tint(AppTheme.primary)
                            }
                    }

                    Button("Add device", systemImage: "plus") {
                        isAddingDevice = true
                    }
                    .accessibilityIdentifier("add-device-button")
                }
            }

            if !archivedDevices.isEmpty {
                Section("Archived") {
                    ForEach(archivedDevices) { device in
                        HStack {
                            deviceRow(device)
                            Spacer()
                            Button("Restore") {
                                restore(device)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Recent usage") {
                if recentUsageSessions.isEmpty {
                    ContentUnavailableView(
                        "No Usage Recorded",
                        systemImage: "clock.badge.plus",
                        description: Text("Record a session to start tracking screen time.")
                    )
                } else {
                    ForEach(recentUsageSessions) { session in
                        usageRow(session)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                sessionToEdit = session
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash") {
                                    sessionToDelete = session
                                }
                                .tint(AppTheme.danger)

                                Button("Edit", systemImage: "pencil") {
                                    sessionToEdit = session
                                }
                                .tint(AppTheme.primary)
                            }
                    }
                }

                Button("Record screen time", systemImage: "plus.circle.fill") {
                    isAddingUsage = true
                }
                .disabled(activeDevices.isEmpty)
                .accessibilityIdentifier("add-usage-button")

                if activeDevices.isEmpty {
                    Text("Add an active device before recording screen time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(child.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add device", systemImage: "plus") {
                    isAddingDevice = true
                }
            }
        }
        .sheet(isPresented: $isAddingDevice) {
            DeviceFormView(child: child)
        }
        .sheet(isPresented: $isAddingUsage) {
            UsageEntryView(child: child, devices: activeDevices)
        }
        .sheet(
            isPresented: Binding(
                get: { sessionToEdit != nil },
                set: { if !$0 { sessionToEdit = nil } }
            )
        ) {
            if let sessionToEdit {
                UsageEntryView(
                    child: child,
                    devices: allDevices.filter { $0.child?.id == child.id },
                    session: sessionToEdit
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { deviceToEdit != nil },
                set: { if !$0 { deviceToEdit = nil } }
            )
        ) {
            if let deviceToEdit {
                DeviceFormView(child: child, device: deviceToEdit)
            }
        }
        .confirmationDialog(
            "Archive this device?",
            isPresented: Binding(
                get: { deviceToArchive != nil },
                set: { if !$0 { deviceToArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                if let deviceToArchive {
                    archive(deviceToArchive)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past screen-time history will be kept, and you can restore the device later.")
        }
        .confirmationDialog(
            "Delete this usage session?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let sessionToDelete {
                    delete(sessionToDelete)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session permanently and cannot be undone.")
        }
        .tint(AppTheme.primary)
    }

    private func deviceRow(_ device: Device) -> some View {
        let usedToday = UsageAggregator.totalMinutes(
            on: .now,
            deviceID: device.id,
            sessions: allUsageSessions
        )

        return HStack(spacing: 14) {
            Image(systemName: device.kind.systemImage)
                .font(.title2)
                .frame(width: 34)
                .foregroundStyle(AppTheme.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.headline)
                Text(device.kind.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(UsageAggregator.format(minutes: usedToday))
                    .font(.headline.monospacedDigit())
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(device.isActive ? "Opens device settings" : "Archived device")
    }

    private func archive(_ device: Device) {
        device.isActive = false
        device.updatedAt = .now
        try? modelContext.save()
        deviceToArchive = nil
    }

    private func usageRow(_ session: UsageSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.device?.kind.systemImage ?? "display")
                .frame(width: 28)
                .foregroundStyle(AppTheme.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.device?.name ?? "Unknown device")
                    .font(.headline)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(session.formattedDuration)
                .font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usage-session-row")
        .accessibilityHint("Opens usage session for editing")
    }

    private func restore(_ device: Device) {
        device.isActive = true
        device.updatedAt = .now
        try? modelContext.save()
    }

    private func delete(_ session: UsageSession) {
        modelContext.delete(session)
        try? modelContext.save()
        sessionToDelete = nil
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
    NavigationStack {
        ChildDetailView(child: ChildProfile(name: "Sam"))
    }
    .modelContainer(
        for: [ParentProfile.self, ChildProfile.self, Device.self, UsageSession.self],
        inMemory: true
    )
}
