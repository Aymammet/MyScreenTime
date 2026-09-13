import PhotosUI
import SwiftData
import SwiftUI

struct ChildSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allChildren: [ChildProfile]
    @Query private var allUsageSessions: [UsageSession]

    let parent: ParentProfile
    let child: ChildProfile

    @State private var name: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var dailyLimitMinutes: Int
    @State private var usesSchedule: Bool
    @State private var weekdayLimitMinutes: Int
    @State private var weekendLimitMinutes: Int
    @State private var saveErrorMessage: String?

    init(parent: ParentProfile, child: ChildProfile) {
        self.parent = parent
        self.child = child
        _name = State(initialValue: child.name)
        _photoData = State(initialValue: child.profilePhotoData)
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
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoData == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                    }
                    if photoData != nil {
                        Button("Remove", role: .destructive) { photoData = nil }
                    }
                }

                TextField("Child's name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("settings-child-name")
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
        .alert("Couldn’t Save Child", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) { Button("OK") {} } message: { Text(saveErrorMessage ?? "Please try again.") }
    }

    private var avatar: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(AppTheme.primary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private var usageSection: some View {
        let calendar = Calendar.current
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
        child.name = normalizedName
        child.profilePhotoData = photoData
        child.dailyLimitMinutes = dailyLimitMinutes
        child.weekdayLimitMinutes = usesSchedule ? weekdayLimitMinutes : nil
        child.weekendLimitMinutes = usesSchedule ? weekendLimitMinutes : nil
        child.updatedAt = .now
        do { try modelContext.save() } catch { saveErrorMessage = error.localizedDescription }
    }
}
