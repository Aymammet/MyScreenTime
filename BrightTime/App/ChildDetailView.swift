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
        allDevices.filter { $0.isActive && $0.isAvailable(to: child.id) }
    }

    private var archivedDevices: [Device] {
        allDevices.filter { !$0.isActive && $0.isAvailable(to: child.id) }
    }

    private var recentUsageSessions: [UsageSession] {
        Array(allUsageSessions.filter { $0.child?.id == child.id }.prefix(10))
    }

    private var todaySummary: DailyUsageSummary {
        UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)
    }

    private var deviceUsageToday: [(device: Device, minutes: Int)] {
        activeDevices
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

    var body: some View {
        List {
            Section {
                heroCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
                    if deviceUsageToday.count > 1 {
                        deviceProportionBar
                            .listRowSeparator(.hidden)
                    }

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

                Button {
                    isAddingUsage = true
                } label: {
                    Label("Record screen time", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .controlSize(.large)
                .disabled(activeDevices.isEmpty)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("add-usage-button")

                if activeDevices.isEmpty {
                    Text("Add an active device before recording screen time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .contentMargins(.bottom, 100, for: .scrollContent)
        .navigationTitle(child.name)
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
                    devices: allDevices.filter { $0.isAvailable(to: child.id) },
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

    private var heroCard: some View {
        let statusColor = AppTheme.statusColor(for: todaySummary.status)

        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                ChildAvatarView(child: child, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.name)
                        .font(.title3.bold())
                    Text(todaySummary.headline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                Spacer()
            }

            ZStack {
                RingProgressView(progress: todaySummary.progress, color: statusColor, size: 116, lineWidth: 10)
                VStack(spacing: 2) {
                    Text("\(todaySummary.usedMinutes)")
                        .font(.system(size: 30, weight: .bold))
                        .accessibilityIdentifier("today-used-total")
                    Text("of \(todaySummary.limitMinutes) min")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today's screen-time progress")
            .accessibilityValue("\(todaySummary.usedMinutes) of \(todaySummary.limitMinutes) minutes")

            Text(todaySummary.remainingHeadline.appending(" today"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(statusColor)
                .accessibilityIdentifier("today-limit-balance")

            Text("\(child.formattedLimit(on: .now)) limit today")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private var deviceProportionBar: some View {
        let entries = deviceUsageToday
        let total = max(entries.reduce(0) { $0 + $1.minutes }, 1)

        return GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(entries, id: \.device.id) { entry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.color(forDeviceID: entry.device.id))
                        .frame(width: max(geometry.size.width * CGFloat(entry.minutes) / CGFloat(total) - 3, 4))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func deviceRow(_ device: Device) -> some View {
        let usedToday = UsageAggregator.totalMinutes(
            on: .now,
            childID: child.id,
            deviceID: device.id,
            sessions: allUsageSessions
        )
        let deviceColor = AppTheme.color(forDeviceID: device.id)

        return HStack(spacing: 14) {
            Image(systemName: device.kind.systemImage)
                .font(.title3)
                .foregroundStyle(deviceColor)
                .frame(width: 36, height: 36)
                .background(deviceColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.headline)
                Text(device.isShared ? "\(device.kind.title) • Shared" : device.kind.title)
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
        let deviceColor = session.device.map { AppTheme.color(forDeviceID: $0.id) } ?? AppTheme.textTertiary

        return HStack(spacing: 12) {
            Image(systemName: session.device?.kind.systemImage ?? "display")
                .font(.subheadline)
                .foregroundStyle(deviceColor)
                .frame(width: 32, height: 32)
                .background(deviceColor.opacity(0.12), in: Circle())
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
