import SwiftData
import SwiftUI

struct ParentSetupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notificationsEnabled = true
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
                    Text("This name is used only to personalize your MyScreenTime experience.")
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
            timeZoneIdentifier: TimeZone.current.identifier
        )

        modelContext.insert(profile)
        try? modelContext.save()
    }
}
