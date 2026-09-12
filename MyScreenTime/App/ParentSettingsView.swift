import SwiftData
import SwiftUI

struct ParentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let parent: ParentProfile

    @State private var name: String
    @State private var notificationsEnabled: Bool

    init(parent: ParentProfile) {
        self.parent = parent
        _name = State(initialValue: parent.name)
        _notificationsEnabled = State(initialValue: parent.notificationsEnabled)
    }

    private var isNameValid: Bool {
        ParentProfile.isValidName(name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Parent profile") {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)

                    if !name.isEmpty, !isNameValid {
                        Text("Enter a name between 2 and 50 characters.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                Section("Preferences") {
                    Toggle("Screen-time notifications", isOn: $notificationsEnabled)
                    LabeledContent("Time zone", value: parent.timeZoneIdentifier)
                }
            }
            .navigationTitle("Parent Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isNameValid)
                }
            }
        }
    }

    private func saveChanges() {
        parent.name = ParentProfile.normalizedName(name)
        parent.notificationsEnabled = notificationsEnabled
        parent.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
