import SwiftData
import SwiftUI

struct UsageEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var timerManager: ScreenTimerManager
    @Query private var allUsageSessions: [UsageSession]

    let child: ChildProfile
    let devices: [Device]
    let session: UsageSession?

    @State private var selectedDeviceID: UUID
    @State private var usageDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var note: String
    @State private var saveErrorMessage: String?

    init(child: ChildProfile, devices: [Device], session: UsageSession? = nil) {
        self.child = child
        self.devices = devices
        self.session = session
        // New entries default to the last 30 minutes (never the future).
        let defaultEnd = Date.now
        let defaultStart = defaultEnd.addingTimeInterval(-30 * 60)
        _selectedDeviceID = State(initialValue: session?.device?.id ?? devices.first?.id ?? UUID())
        _usageDate = State(initialValue: session?.startedAt ?? defaultStart)
        _startTime = State(initialValue: session?.startedAt ?? defaultStart)
        _endTime = State(initialValue: session?.endedAt ?? defaultEnd)
        _note = State(initialValue: session?.note ?? "")
    }

    private var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    private var combinedStart: Date? {
        combine(date: usageDate, time: startTime)
    }

    /// An end time earlier than the start means the session ran past midnight.
    private var combinedEnd: Date? {
        guard let combinedStart, let end = combine(date: usageDate, time: endTime) else { return nil }
        if end <= combinedStart {
            return Calendar.current.date(byAdding: .day, value: 1, to: end)
        }
        return end
    }

    private var endsNextDay: Bool {
        guard let combinedStart, let combinedEnd else { return false }
        return !Calendar.current.isDate(combinedStart, inSameDayAs: combinedEnd)
    }

    private var durationMinutes: Int? {
        guard let combinedStart, let combinedEnd,
              combine(date: usageDate, time: endTime) != combinedStart else { return nil }
        return try? DurationCalculator.minutes(from: combinedStart, to: combinedEnd)
    }

    /// Usage can only be logged for time that has already happened.
    private var isFutureDate: Bool {
        guard let combinedEnd else { return false }
        return combinedEnd > Date.now.addingTimeInterval(60)
    }

    /// A running timer for this child already covers this time.
    private var overlapsRunningTimer: Bool {
        guard session == nil,
              let combinedStart, let combinedEnd,
              let timer = timerManager.timer(for: child.id) else { return false }
        let timerEnd = min(Date.now, timer.endsAt)
        return combinedStart < timerEnd && combinedEnd > timer.startedAt
    }

    private var hasOverlap: Bool {
        guard let combinedStart, let combinedEnd else { return false }
        return UsageSession.hasOverlap(
            startedAt: combinedStart,
            endedAt: combinedEnd,
            childID: child.id,
            excluding: session?.id,
            among: allUsageSessions
        )
    }

    private var isValid: Bool {
        selectedDevice != nil && durationMinutes != nil && !isFutureDate && !hasOverlap && !overlapsRunningTimer
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Usage") {
                    Picker("Device", selection: $selectedDeviceID) {
                        ForEach(devices) { device in
                            Label(
                                device.isShared ? "\(device.name) (Shared)" : device.name,
                                systemImage: device.kind.systemImage
                            )
                                .tag(device.id)
                        }
                    }
                    .accessibilityIdentifier("usage-device-picker")

                    DatePicker("Date", selection: $usageDate, displayedComponents: .date)
                        .accessibilityIdentifier("usage-date-picker")

                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("usage-start-picker")

                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("usage-end-picker")
                }

                Section("Calculated duration") {
                    if let durationMinutes {
                        LabeledContent("Screen time", value: "\(durationMinutes) minutes")
                            .accessibilityIdentifier("duration-preview")
                        if endsNextDay {
                            Label("Ends the next day", systemImage: "moon.stars")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else {
                        Label("Start and end can't be the same time.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.dangerText)
                    }

                    if isFutureDate {
                        Text("Usage can only be logged for time that has already happened.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.dangerText)
                    }

                    if overlapsRunningTimer {
                        Label(
                            "A timer is running for \(child.name) during this time. It will be recorded when it ends.",
                            systemImage: "timer"
                        )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.dangerText)
                        .accessibilityIdentifier("timer-overlap-warning")
                    }

                    if hasOverlap {
                        Label(
                            "This time overlaps another session for \(child.name).",
                            systemImage: "rectangle.2.swap"
                        )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.danger)
                        .accessibilityIdentifier("overlap-warning")
                    }
                }

                Section("Note (optional)") {
                    TextField("What was the screen used for?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("usage-note-field")
                }
            }
            .navigationTitle(session == nil ? "Add Usage" : "Edit Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveUsage()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("save-usage")
                }
            }
            .alert(
                "Couldn’t Save Usage",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK") {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "Please try again.")
            }
        }
    }

    private func combine(date: Date, time: Date) -> Date? {
        let calendar = Calendar.current
        let dateParts = calendar.dateComponents([.year, .month, .day], from: date)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)

        var components = DateComponents()
        components.year = dateParts.year
        components.month = dateParts.month
        components.day = dateParts.day
        components.hour = timeParts.hour
        components.minute = timeParts.minute
        return calendar.date(from: components)
    }

    private func saveUsage() {
        guard
            let selectedDevice,
            let combinedStart,
            let combinedEnd,
            isValid
        else { return }

        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session {
            session.startedAt = combinedStart
            session.endedAt = combinedEnd
            session.note = normalizedNote.isEmpty ? nil : normalizedNote
            session.device = selectedDevice
            session.updatedAt = .now
        } else {
            modelContext.insert(
                UsageSession(
                    startedAt: combinedStart,
                    endedAt: combinedEnd,
                    note: normalizedNote.isEmpty ? nil : normalizedNote,
                    child: child,
                    device: selectedDevice
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}
