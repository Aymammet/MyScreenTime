import SwiftData
import SwiftUI

struct ParentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]

    let parent: ParentProfile

    @State private var name: String
    @State private var notificationsEnabled: Bool
    @State private var selectedAvatar: DefaultProfileAvatar

    init(parent: ParentProfile) {
        self.parent = parent
        _name = State(initialValue: parent.name)
        _notificationsEnabled = State(initialValue: parent.notificationsEnabled)
        _selectedAvatar = State(initialValue: parent.resolvedDefaultAvatar)
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
                    HStack(spacing: 14) {
                        Image(selectedAvatar.assetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())

                        Text("Choose the profile shown on your BrightTime home screen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)

                    if !name.isEmpty, !isNameValid {
                        Text("Enter a name between 2 and 50 characters.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                    }

                    DefaultAvatarPicker(
                        avatars: DefaultProfileAvatar.allCases,
                        selection: $selectedAvatar
                    )
                    .accessibilityIdentifier("settings-parent-default-avatar-picker")
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
        parent.defaultAvatar = selectedAvatar
        parent.notificationsEnabled = notificationsEnabled
        parent.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
