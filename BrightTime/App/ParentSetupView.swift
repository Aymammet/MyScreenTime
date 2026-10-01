import SwiftData
import SwiftUI

struct ParentSetupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notificationsEnabled = true
    @State private var selectedAvatar: DefaultProfileAvatar = .boy1
    @FocusState private var isNameFocused: Bool

    private var normalizedName: String {
        ParentProfile.normalizedName(name)
    }

    private var isNameValid: Bool {
        ParentProfile.isValidName(name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                        .accessibilityIdentifier("parent-name-field")

                    if !name.isEmpty, !isNameValid {
                        Text("Enter a name between 2 and 50 characters.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                    }
                } header: {
                    Text("Parent profile")
                } footer: {
                    Text("This name is used only to personalize your BrightTime experience.")
                }

                Section {
                    DefaultAvatarPicker(
                        avatars: DefaultProfileAvatar.allCases,
                        selection: $selectedAvatar
                    )
                    .accessibilityIdentifier("parent-default-avatar-picker")
                } header: {
                    Text("Choose your profile photo")
                } footer: {
                    Text("You can change this later in Parent Settings.")
                }

                Section("Preferences") {
                    Toggle("Screen-time notifications", isOn: $notificationsEnabled)

                    LabeledContent(
                        "Time zone",
                        value: TimeZone.current.localizedName(for: .standard, locale: .current)
                            ?? TimeZone.current.identifier
                    )
                }

                Section {
                    Button("Save and continue") {
                        saveProfile()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!isNameValid)
                    .accessibilityIdentifier("save-parent-profile")
                }
            }
            .navigationTitle("Welcome")
            .onAppear {
                isNameFocused = true
            }
        }
        .tint(AppTheme.primary)
    }

    private func saveProfile() {
        let profile = ParentProfile(
            name: normalizedName,
            notificationsEnabled: notificationsEnabled,
            timeZoneIdentifier: TimeZone.current.identifier,
            defaultAvatar: selectedAvatar
        )

        modelContext.insert(profile)
        try? modelContext.save()
    }
}
