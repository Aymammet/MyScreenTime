import SwiftData
import SwiftUI

struct DeviceFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allDevices: [Device]

    let child: ChildProfile
    let device: Device?

    @State private var name: String
    @State private var kind: Device.Kind
    @State private var saveErrorMessage: String?

    init(child: ChildProfile, device: Device? = nil) {
        self.child = child
        self.device = device
        _name = State(initialValue: device?.name ?? "")
        _kind = State(initialValue: device?.kind ?? .phone)
    }

    private var normalizedName: String {
        Device.normalizedName(name)
    }

    private var hasDuplicateName: Bool {
        allDevices.contains { candidate in
            candidate.child?.id == child.id
                && candidate.id != device?.id
                && candidate.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    private var isValid: Bool {
        Device.isValidName(name) && !hasDuplicateName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    TextField("Device name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("device-name-field")

                    if !name.isEmpty, !Device.isValidName(name) {
                        validationMessage("Enter a name between 2 and 50 characters.")
                    } else if hasDuplicateName {
                        validationMessage("This child already has a device with that name.")
                    }

                    Picker("Type", selection: $kind) {
                        ForEach(Device.Kind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }
                    .accessibilityIdentifier("device-kind-picker")
                }
            }
            .navigationTitle(device == nil ? "Add Device" : "Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDevice()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("save-device")
                }
            }
            .alert(
                "Couldn’t Save Device",
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

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.danger)
    }

    private func saveDevice() {
        if let device {
            device.name = normalizedName
            device.kind = kind
            device.updatedAt = .now
        } else {
            modelContext.insert(
                Device(
                    name: normalizedName,
                    kind: kind,
                    child: child
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
