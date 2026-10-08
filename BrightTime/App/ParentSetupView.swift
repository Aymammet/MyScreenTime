import PhotosUI
import SwiftData
import SwiftUI

struct ParentSetupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notificationsEnabled = true
    @State private var selectedAvatar: DefaultProfileAvatar = .boy1
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
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
                        .onChange(of: name) { _, newValue in
                            name = String(newValue.prefix(ParentProfile.maximumNameLength))
                        }

                    if !name.isEmpty, !isNameValid {
                        Text("Enter a name between 2 and 16 characters.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                    }
                } header: {
                    Text("Parent profile")
                } footer: {
                    Text("This name is used only to personalize your BrightTime experience.")
                }

                Section {
                    HStack(spacing: 16) {
                        profileAvatar

                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Choose profile photo", systemImage: "photo")
                            }

                            if photoData != nil {
                                Button("Use a default avatar", role: .destructive) {
                                    photoData = nil
                                }
                                .font(.caption)
                            }
                        }
                    }

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
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = resizedPhotoData(data)
                }
            }
        }
        .tint(AppTheme.primary)
    }

    private var profileAvatar: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(selectedAvatar.assetName).resizable().scaledToFill()
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white, lineWidth: 2) }
    }

    private func resizedPhotoData(_ data: Data) -> Data? {
        guard let source = UIImage(data: data) else { return nil }
        let scale = min(512 / max(source.size.width, source.size.height), 1)
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.82) { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func saveProfile() {
        let profile = ParentProfile(
            name: normalizedName,
            notificationsEnabled: notificationsEnabled,
            timeZoneIdentifier: TimeZone.current.identifier,
            defaultAvatar: selectedAvatar,
            profilePhotoData: photoData
        )

        modelContext.insert(profile)
        try? modelContext.save()
    }
}
