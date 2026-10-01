import PhotosUI
import SwiftData
import SwiftUI

struct ChildFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allChildren: [ChildProfile]

    let parent: ParentProfile
    let child: ChildProfile?

    @State private var name: String
    @State private var selectedGender: ChildGender
    @State private var selectedAvatar: DefaultProfileAvatar
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var dailyLimitMinutes: Int
    @State private var usesSchedule: Bool
    @State private var weekdayLimitMinutes: Int
    @State private var weekendLimitMinutes: Int
    @State private var selectedColor: ChildColor
    @State private var saveErrorMessage: String?

    init(parent: ParentProfile, child: ChildProfile? = nil) {
        self.parent = parent
        self.child = child
        _name = State(initialValue: child?.name ?? "")
        _selectedGender = State(initialValue: child?.resolvedGender ?? .boy)
        _selectedAvatar = State(initialValue: child?.resolvedDefaultAvatar ?? .boy1)
        _photoData = State(initialValue: child?.profilePhotoData)
        _dailyLimitMinutes = State(initialValue: child?.dailyLimitMinutes ?? 120)
        _usesSchedule = State(initialValue: child?.weekdayLimitMinutes != nil && child?.weekendLimitMinutes != nil)
        _weekdayLimitMinutes = State(initialValue: child?.weekdayLimitMinutes ?? child?.dailyLimitMinutes ?? 120)
        _weekendLimitMinutes = State(initialValue: child?.weekendLimitMinutes ?? child?.dailyLimitMinutes ?? 120)
        _selectedColor = State(initialValue: child?.color ?? ChildColor.allCases.randomElement() ?? .teal)
    }

    private var normalizedName: String {
        ChildProfile.normalizedName(name)
    }

    private var hasDuplicateName: Bool {
        allChildren.contains { candidate in
            candidate.parent?.id == parent.id
                && candidate.id != child?.id
                && candidate.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    private var isValid: Bool {
        ChildProfile.isValidName(name)
            && ChildProfile.isValidDailyLimit(dailyLimitMinutes)
            && (!usesSchedule || (
                ChildProfile.isValidDailyLimit(weekdayLimitMinutes)
                    && ChildProfile.isValidDailyLimit(weekendLimitMinutes)
            ))
            && !hasDuplicateName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        profileAvatar

                        VStack(alignment: .leading, spacing: 8) {
                            if photoData == nil {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("Choose photo", systemImage: "photo")
                                }
                            } else {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("Change photo", systemImage: "photo")
                                }
                                Button("Use default", role: .destructive) { photoData = nil }
                                    .font(.caption)
                            }
                        }
                    }

                    TextField("Child's name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("child-name-field")

                    if !name.isEmpty, !ChildProfile.isValidName(name) {
                        validationMessage("Enter a name between 2 and 50 characters.")
                    } else if hasDuplicateName {
                        validationMessage("A child with this name already exists.")
                    }
                } header: {
                    Text("Child profile")
                }

                Section {
                    Picker("Gender", selection: $selectedGender) {
                        ForEach(ChildGender.allCases) { gender in
                            Text(gender.title).tag(gender)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("child-gender-picker")

                    DefaultAvatarPicker(
                        avatars: selectedGender.avatarChoices,
                        selection: $selectedAvatar
                    )
                    .accessibilityIdentifier("child-default-avatar-picker")
                } header: {
                    Text("Default profile photo")
                } footer: {
                    Text("BrightTime uses the matching default avatar until you choose a photo from this phone.")
                }

                Section {
                    ColorSwatchPicker(selection: $selectedColor)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("child-color-picker")
                } header: {
                    Text("Color")
                } footer: {
                    Text("Used on the dashboard and charts so this child is easy to tell apart from siblings.")
                }

                Section {
                    Toggle("Different weekend limit", isOn: $usesSchedule)
                        .accessibilityIdentifier("weekend-limit-toggle")

                    if usesSchedule {
                        limitStepper("Weekday limit", value: $weekdayLimitMinutes)
                            .accessibilityIdentifier("weekday-limit-stepper")
                        limitStepper("Weekend limit", value: $weekendLimitMinutes)
                            .accessibilityIdentifier("weekend-limit-stepper")
                    } else {
                        limitStepper("Daily limit", value: $dailyLimitMinutes)
                            .accessibilityIdentifier("daily-limit-stepper")
                    }
                } footer: {
                    Text(usesSchedule
                         ? "Weekday limits apply Monday through Friday; weekend limits apply Saturday and Sunday."
                         : "This limit applies every day to the child's combined use across all devices.")
                }
            }
            .navigationTitle(child == nil ? "Add Child" : "Edit Child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChild()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("save-child-profile")
                }
            }
            .alert(
                "Couldn’t Save Child",
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
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = resizedPhotoData(data)
                }
            }
            .onChange(of: selectedGender) { _, gender in
                if selectedAvatar.gender != gender {
                    selectedAvatar = gender.avatarChoices[0]
                }
            }
        }
    }

    private var profileAvatar: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(selectedAvatar.assetName)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white, lineWidth: 2) }
        .shadow(color: selectedColor.color.opacity(0.2), radius: 5, y: 2)
    }

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.danger)
    }

    private func formattedLimit(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private func limitStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 15...1_440, step: 15) {
            LabeledContent(title, value: formattedLimit(value.wrappedValue))
        }
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

    private func saveChild() {
        if let child {
            child.name = normalizedName
            child.gender = selectedGender
            child.defaultAvatar = selectedAvatar
            child.profilePhotoData = photoData
            child.dailyLimitMinutes = dailyLimitMinutes
            child.weekdayLimitMinutes = usesSchedule ? weekdayLimitMinutes : nil
            child.weekendLimitMinutes = usesSchedule ? weekendLimitMinutes : nil
            child.color = selectedColor
            child.updatedAt = .now
        } else {
            modelContext.insert(
                ChildProfile(
                    name: normalizedName,
                    dailyLimitMinutes: dailyLimitMinutes,
                    weekdayLimitMinutes: usesSchedule ? weekdayLimitMinutes : nil,
                    weekendLimitMinutes: usesSchedule ? weekendLimitMinutes : nil,
                    profilePhotoData: photoData,
                    gender: selectedGender,
                    defaultAvatar: selectedAvatar,
                    colorRawValue: selectedColor.rawValue,
                    parent: parent
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
