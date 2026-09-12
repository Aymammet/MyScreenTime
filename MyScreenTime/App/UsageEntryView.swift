import SwiftData
import SwiftUI

struct UsageEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
        _selectedDeviceID = State(initialValue: session?.device?.id ?? devices.first?.id ?? UUID())
        _usageDate = State(initialValue: session?.startedAt ?? .now)
        _startTime = State(initialValue: session?.startedAt ?? .now)
        _endTime = State(initialValue: session?.endedAt ?? Date().addingTimeInterval(30 * 60))
        _note = State(initialValue: session?.note ?? "")
    }

    private var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    private var combinedStart: Date? {
        combine(date: usageDate, time: startTime)
    }

    private var combinedEnd: Date? {
        combine(date: usageDate, time: endTime)
    }

    private var durationMinutes: Int? {
        guard let combinedStart, let combinedEnd else { return nil }
        return try? DurationCalculator.minutes(from: combinedStart, to: combinedEnd)
    }

    private var isFutureDate: Bool {
        Calendar.current.startOfDay(for: usageDate) > Calendar.current.startOfDay(for: .now)
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
        selectedDevice != nil && durationMinutes != nil && !isFutureDate && !hasOverlap
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Usage") {
                    Picker("Device", selection: $selectedDeviceID) {
                        ForEach(devices) { device in
                            Label(device.name, systemImage: device.kind.systemImage)
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
                    } else {
                        Label("End time must be later than start time.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.danger)
                    }

                    if isFutureDate {
                        Text("Usage cannot be recorded for a future date.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
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
