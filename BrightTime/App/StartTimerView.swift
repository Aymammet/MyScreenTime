import SwiftUI

struct StartTimerView: View {
    @Environment(\.dismiss) private var dismiss

    let child: ChildProfile
    let devices: [Device]
    let todaySummary: DailyUsageSummary
    let onStart: (Device, Int, Bool, Bool) -> Void

    @State private var selectedDeviceID: UUID?
    @State private var minutes = 30
    @State private var notifyWhenFinished = true
    @State private var showOnLockScreen = true
    @State private var isShowingLimitWarning = false

    private var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    Picker("Device", selection: $selectedDeviceID) {
                        ForEach(devices) { device in
                            Text(device.isShared ? "\(device.name) (Shared)" : device.name)
                                .tag(Optional(device.id))
                        }
                    }
                    .accessibilityIdentifier("timer-device-picker")
                }

                Section {
                    Stepper(value: $minutes, in: 5...240, step: 5) {
                        LabeledContent("Duration", value: "\(minutes) min")
                    }
                    .accessibilityIdentifier("timer-duration-stepper")
                } header: {
                    Text("Timer")
                } footer: {
                    Text("The completed timer is added to today’s usage automatically.")
                }

                Section {
                    Toggle(isOn: $notifyWhenFinished) {
                        Label("Notify when timer ends", systemImage: "bell.fill")
                    }
                    .accessibilityIdentifier("timer-notification-toggle")

                    Toggle(isOn: $showOnLockScreen) {
                        Label("Show on Lock Screen", systemImage: "iphone")
                    }
                    .accessibilityIdentifier("timer-lock-screen-toggle")
                } header: {
                    Text("Timer options")
                } footer: {
                    Text("Lock Screen display also appears in the Dynamic Island on supported iPhones.")
                }
            }
            .navigationTitle("Start Timer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { selectedDeviceID = selectedDeviceID ?? devices.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        if limitWarningMessage == nil {
                            startTimer()
                        } else {
                            isShowingLimitWarning = true
                        }
                    }
                    .disabled(selectedDevice == nil)
                    .accessibilityIdentifier("confirm-start-timer")
                }
            }
            .alert("Daily limit warning", isPresented: $isShowingLimitWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Start anyway") { startTimer() }
            } message: {
                Text(limitWarningMessage ?? "This timer may exceed today’s limit.")
            }
        }
    }

    private var limitWarningMessage: String? {
        let remaining = todaySummary.remainingMinutes
        if todaySummary.usedMinutes >= todaySummary.limitMinutes {
            return "\(child.name) has reached today’s limit. Do you still want to start this timer?"
        }
        guard minutes > remaining else { return nil }
        let overage = minutes - remaining
        return "\(child.name) has only \(minuteText(remaining)) left today. A \(minuteText(minutes)) timer will put \(child.name) \(minuteText(overage)) over the limit. Do you want to continue?"
    }

    private func minuteText(_ value: Int) -> String {
        "\(value) minute\(value == 1 ? "" : "s")"
    }

    private func startTimer() {
        guard let selectedDevice else { return }
        onStart(selectedDevice, minutes, notifyWhenFinished, showOnLockScreen)
        dismiss()
    }
}
