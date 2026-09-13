import SwiftData
import SwiftUI

struct ParentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]

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

    private var children: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id }
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

                Section("Children") {
                    if children.isEmpty {
                        Text("No children added yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(children) { child in
                            NavigationLink {
                                ChildSettingsView(parent: parent, child: child)
                            } label: {
                                HStack(spacing: 12) {
                                    ChildAvatarView(child: child, size: 40)
                                    VStack(alignment: .leading) {
                                        Text(child.name).font(.headline)
                                        Text(child.isActive ? "Active" : "Archived")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
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
