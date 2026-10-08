import PhotosUI
import SwiftData
import SwiftUI

struct ParentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]

    let parent: ParentProfile
    let onSignOut: () -> Void

    @State private var name: String
    @State private var notificationsEnabled: Bool
    @State private var selectedAvatar: DefaultProfileAvatar
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isConfirmingSignOut = false

    init(parent: ParentProfile, onSignOut: @escaping () -> Void = {}) {
        self.parent = parent
        self.onSignOut = onSignOut
        _name = State(initialValue: parent.name)
        _notificationsEnabled = State(initialValue: parent.notificationsEnabled)
        _selectedAvatar = State(initialValue: parent.resolvedDefaultAvatar)
        _photoData = State(initialValue: parent.profilePhotoData)
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
                        profileAvatar

                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Choose profile photo", systemImage: "photo")
                            }
                            .accessibilityIdentifier("settings-parent-photo-picker")

                            if photoData != nil {
                                Button("Use a default avatar", role: .destructive) {
                                    photoData = nil
                                }
                                .font(.caption)
                            }

                            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                isConfirmingSignOut = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("parent-sign-out-button")
                        }
                    }

                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { _, newValue in
                            name = String(newValue.prefix(ParentProfile.maximumNameLength))
                        }

                    if !name.isEmpty, !isNameValid {
                        Text("Enter a name between 2 and 16 characters.")
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
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = resizedPhotoData(data)
                }
            }
            .confirmationDialog(
                "Sign out of BrightTime?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    onSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your family data will remain on this device.")
            }
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

    private var profileAvatar: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(selectedAvatar.assetName).resizable().scaledToFill()
            }
        }
        .frame(width: 68, height: 68)
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

    private func saveChanges() {
        parent.name = ParentProfile.normalizedName(name)
        parent.defaultAvatar = selectedAvatar
        parent.profilePhotoData = photoData
        parent.notificationsEnabled = notificationsEnabled
        parent.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
