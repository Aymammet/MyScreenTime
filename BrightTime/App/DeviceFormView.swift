import SwiftData
import SwiftUI

struct DeviceFormView: View {
    private enum OwnerSelection: Hashable {
        case shared
        case child(UUID)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allDevices: [Device]

    let children: [ChildProfile]
    let device: Device?

    @State private var name: String
    @State private var kind: Device.Kind
    @State private var ownerSelection: OwnerSelection
    @State private var saveErrorMessage: String?

    init(child: ChildProfile, device: Device? = nil) {
        self.init(children: [child], device: device, preferredChild: child)
    }

    init(children: [ChildProfile], device: Device? = nil, preferredChild: ChildProfile? = nil) {
        let activeChildren = children.filter(\.isActive)
        self.children = activeChildren
        self.device = device
        _name = State(initialValue: device?.name ?? "")
        _kind = State(initialValue: device?.kind ?? .phone)
        if device?.isShared == true {
            _ownerSelection = State(initialValue: .shared)
        } else if let childID = device?.child?.id ?? preferredChild?.id ?? activeChildren.first?.id {
            _ownerSelection = State(initialValue: .child(childID))
        } else {
            _ownerSelection = State(initialValue: .shared)
        }
    }

    private var selectedChild: ChildProfile? {
        guard case .child(let childID) = ownerSelection else { return nil }
        return children.first { $0.id == childID }
    }

    private var isShared: Bool { ownerSelection == .shared }

    private var normalizedName: String {
        Device.normalizedName(name)
    }

    private var hasDuplicateName: Bool {
        allDevices.contains { candidate in
            candidate.id != device?.id
                && (isShared ? candidate.isShared : (!candidate.isShared && candidate.child?.id == selectedChild?.id))
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
                        validationMessage("This owner already has a device with that name.")
                    }

                    Picker("Type", selection: $kind) {
                        ForEach(Device.Kind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }
                    .accessibilityIdentifier("device-kind-picker")

                    Picker("Who uses this device?", selection: $ownerSelection) {
                        Label("Everyone (shared)", systemImage: "house.fill")
                            .tag(OwnerSelection.shared)

                        ForEach(children) { child in
                            Label(child.name, systemImage: "person.fill")
                                .tag(OwnerSelection.child(child.id))
                        }
                    }
                    .accessibilityIdentifier("device-owner-picker")
                }

                Section {
                    Text(
                        isShared
                            ? "Everyone in the family can select this device. Each usage session is still assigned to the child who used it."
                            : "This device is assigned only to \(selectedChild?.name ?? "the selected child")."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            device.isShared = isShared
            device.child = selectedChild
            device.updatedAt = .now
        } else {
            modelContext.insert(
                Device(
                    name: normalizedName,
                    kind: kind,
                    isShared: isShared,
                    child: selectedChild
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
