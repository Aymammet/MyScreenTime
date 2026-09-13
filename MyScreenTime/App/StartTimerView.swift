import SwiftUI

struct StartTimerView: View {
    @Environment(\.dismiss) private var dismiss

    let child: ChildProfile
    let devices: [Device]
    let onStart: (Device, Int) -> Void

    @State private var selectedDeviceID: UUID?
    @State private var minutes = 30

    private var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    Picker("Device", selection: $selectedDeviceID) {
                        ForEach(devices) { device in
                            Text(device.name).tag(Optional(device.id))
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
                    Text("You’ll receive a notification when \(child.name)’s time is over. The completed timer is added to today’s usage automatically.")
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
                        guard let selectedDevice else { return }
                        onStart(selectedDevice, minutes)
                        dismiss()
                    }
                    .disabled(selectedDevice == nil)
                    .accessibilityIdentifier("confirm-start-timer")
                }
            }
        }
    }
}
