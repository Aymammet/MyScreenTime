import PhotosUI
import SwiftData
import SwiftUI

struct ChildSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var timerManager: ScreenTimerManager
    @Query private var allChildren: [ChildProfile]
    @Query private var allDevices: [Device]
    @Query private var allUsageSessions: [UsageSession]

    let parent: ParentProfile
    let child: ChildProfile

    @State private var name: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var selectedGender: ChildGender
    @State private var selectedAvatar: DefaultProfileAvatar
    @State private var selectedColor: ChildColor
    @State private var dailyLimitMinutes: Int
    @State private var usesSchedule: Bool
    @State private var weekdayLimitMinutes: Int
    @State private var weekendLimitMinutes: Int
    @State private var saveErrorMessage: String?
    @State private var errorTitle = "Couldn’t Save Kid"
    @State private var isConfirmingDelete = false

    init(parent: ParentProfile, child: ChildProfile) {
        self.parent = parent
        self.child = child
        _name = State(initialValue: child.name)
        _photoData = State(initialValue: child.profilePhotoData)
        _selectedGender = State(initialValue: child.resolvedGender)
        _selectedAvatar = State(initialValue: child.resolvedDefaultAvatar)
        _selectedColor = State(initialValue: child.color)
        _dailyLimitMinutes = State(initialValue: child.dailyLimitMinutes)
        _usesSchedule = State(initialValue: child.weekdayLimitMinutes != nil && child.weekendLimitMinutes != nil)
        _weekdayLimitMinutes = State(initialValue: child.weekdayLimitMinutes ?? child.dailyLimitMinutes)
        _weekendLimitMinutes = State(initialValue: child.weekendLimitMinutes ?? child.dailyLimitMinutes)
    }

    private var normalizedName: String { ChildProfile.normalizedName(name) }

    private var isValid: Bool {
        ChildProfile.isValidName(name)
            && !allChildren.contains {
                $0.parent?.id == parent.id && $0.id != child.id
                    && $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
            }
    }

    var body: some View {
        Form {
            Section("Profile") {
                HStack(spacing: 16) {
                    avatar
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

                TextField("Kid's name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("settings-child-name")
                    .onChange(of: name) { _, newValue in
                        name = String(newValue.prefix(ChildProfile.maximumNameLength))
                    }

                Picker("Gender", selection: $selectedGender) {
                    ForEach(ChildGender.allCases) { gender in
                        Text(gender.title).tag(gender)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings-child-gender-picker")

                DefaultAvatarPicker(
                    avatars: selectedGender.avatarChoices,
                    selection: $selectedAvatar
                )
                .accessibilityIdentifier("settings-child-default-avatar-picker")
            }

            Section {
                ColorSwatchPicker(selection: $selectedColor)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("settings-child-color-picker")
            } header: {
                Text("Color")
            } footer: {
                Text("Used on the dashboard and charts so this kid is easy to tell apart from siblings.")
            }

            usageSection

            Section("Screen-time limits") {
                Toggle("Different weekend limit", isOn: $usesSchedule)
                if usesSchedule {
                    limitStepper("Weekday limit", value: $weekdayLimitMinutes)
                    limitStepper("Weekend limit", value: $weekendLimitMinutes)
                } else {
                    limitStepper("Daily limit", value: $dailyLimitMinutes)
                }
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete kid", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .foregroundStyle(AppTheme.dangerText)
                .accessibilityIdentifier("settings-delete-kid")
            } footer: {
                Text("Permanently deletes this kid, their personal devices, usage history, and time-bank activity.")
            }
        }
        .navigationTitle(child.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
                    .accessibilityIdentifier("save-child-settings")
            }
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
        .alert(errorTitle, isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) { Button("OK") {} } message: { Text(saveErrorMessage ?? "Please try again.") }
        .alert("Delete kid?", isPresented: $isConfirmingDelete) {
            Button("Delete \(child.name)", role: .destructive) {
                deleteKid()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(child.name), their personal devices, screen-time history, and time-bank activity. This cannot be undone.")
        }
    }

    private var avatar: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(selectedAvatar.assetName)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private var usageSection: some View {
        let calendar = AppCalendar.day
        let now = Date.now
        let day = calendar.dateInterval(of: .day, for: now)!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let month = calendar.dateInterval(of: .month, for: now)!
        let ids: Set<UUID> = [child.id]

        return Section("Usage summary") {
            LabeledContent("Today", value: UsageAggregator.format(minutes: UsageAggregator.totalMinutes(in: day, childIDs: ids, sessions: allUsageSessions)))
            LabeledContent("This week", value: UsageAggregator.format(minutes: UsageAggregator.totalMinutes(in: week, childIDs: ids, sessions: allUsageSessions)))
            LabeledContent("This month", value: UsageAggregator.format(minutes: UsageAggregator.totalMinutes(in: month, childIDs: ids, sessions: allUsageSessions)))
        }
    }

    private func limitStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 15...1_440, step: 15) {
            LabeledContent(title, value: UsageAggregator.format(minutes: value.wrappedValue))
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

    private func save() {
        errorTitle = "Couldn’t Save Kid"
        child.name = normalizedName
        child.gender = selectedGender
        child.defaultAvatar = selectedAvatar
        child.profilePhotoData = photoData
        child.color = selectedColor
        child.dailyLimitMinutes = dailyLimitMinutes
        child.weekdayLimitMinutes = usesSchedule ? weekdayLimitMinutes : nil
        child.weekendLimitMinutes = usesSchedule ? weekendLimitMinutes : nil
        child.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deleteKid() {
        timerManager.stopTimer(
            forChildID: child.id,
            children: allChildren,
            devices: allDevices,
            context: modelContext
        )
        modelContext.delete(child)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorTitle = "Couldn’t Delete Kid"
            saveErrorMessage = error.localizedDescription
        }
    }
}
