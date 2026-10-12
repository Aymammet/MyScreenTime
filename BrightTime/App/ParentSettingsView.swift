import PhotosUI
import SwiftData
import SwiftUI

/// How BrightTime looks, independent of the iPhone's own setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "brighttime.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The Profile tab: the parent's profile, family features, preferences, security
/// and account. Every change applies right away; only the name and photo have an
/// edit screen with its own Save.
struct ParentSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLock.self) private var lock
    @Environment(FamilySync.self) private var familySync
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]

    let parent: ParentProfile
    let onSignOut: () -> Void

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0

    @State private var isConfirmingSignOut = false
    @State private var passcodeFlow: PasscodeSetupView.Mode?
    @State private var lockAfterPasscodeCreated = false

    init(parent: ParentProfile, onSignOut: @escaping () -> Void = {}) {
        self.parent = parent
        self.onSignOut = onSignOut
    }

    private var children: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                familySection
                preferencesSection
                securitySection
                childrenSection
                accountSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .sheet(isPresented: $isConfirmingSignOut) {
                SignOutSheet {
                    signOut()
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { passcodeFlow != nil },
                    set: { if !$0 { passcodeFlow = nil } }
                ),
                onDismiss: {
                    // Swiping the sheet away must not leave "lock after" armed for
                    // a later, unrelated passcode change.
                    lockAfterPasscodeCreated = false
                }
            ) {
                if let passcodeFlow {
                    PasscodeSetupView(mode: passcodeFlow) { completed in
                        if completed, lockAfterPasscodeCreated {
                            signOut()
                        }
                        lockAfterPasscodeCreated = false
                    }
                }
            }
        }
        .tint(AppTheme.primary)
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            NavigationLink {
                EditParentProfileView(parent: parent)
            } label: {
                HStack(spacing: 14) {
                    ParentAvatarView(parent: parent, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(parent.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text("Edit name & photo")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("profile-edit-link")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var preferencesSection: some View {
        Section {
            Toggle(isOn: notificationsBinding) {
                settingLabel("Notifications", systemImage: "bell.fill", tint: AppTheme.primary)
            }

            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                settingLabel("Appearance", systemImage: "circle.lefthalf.filled", tint: Color(hex: 0x7B61D1))
            }
            .accessibilityIdentifier("settings-appearance-picker")

            NavigationLink {
                TimeAndDaySettingsView()
            } label: {
                LabeledContent {
                    Text(timeSummary)
                        .font(.footnote)
                        .multilineTextAlignment(.trailing)
                } label: {
                    settingLabel("Time & Day", systemImage: "globe", tint: AppTheme.warning)
                }
            }
            .accessibilityIdentifier("settings-time-and-day-link")
        } header: {
            Text("Preferences")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var familySection: some View {
        Section {
            NavigationLink {
                FamilySharingView()
            } label: {
                LabeledContent {
                    Text(familySummary)
                        .font(.footnote)
                } label: {
                    settingLabel("Co-parents", systemImage: "person.2.fill", tint: AppTheme.primary)
                }
            }
            .accessibilityIdentifier("settings-co-parents-link")

            NavigationLink {
                EarnActivitiesView()
            } label: {
                settingLabel("Earn-time activities", systemImage: "star.circle.fill", tint: AppTheme.warning)
            }
            .accessibilityIdentifier("settings-earn-activities-link")
        } header: {
            Text("Family")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var familySummary: String {
        switch familySync.role {
        case .none: "Off"
        case .owner: "Sharing"
        case .member: "Joined"
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        @Bindable var lock = lock

        Section {
            if lock.hasPasscode {
                if lock.biometry != .none {
                    Toggle(isOn: $lock.useBiometrics) {
                        settingLabel("Unlock with \(lock.biometry.name)", systemImage: lock.biometry.systemImage, tint: AppTheme.primary)
                    }
                    .accessibilityIdentifier("settings-biometrics-toggle")

                    if lock.useBiometrics, !lock.isBiometryEnrolled {
                        Label("\(lock.biometry.name) isn't set up on this iPhone yet. Turn it on in iPhone Settings → \(lock.biometry.name) & Passcode.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Picker(selection: $lock.autoLock) {
                    ForEach(AppLock.AutoLock.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    settingLabel("Auto-lock", systemImage: "timer", tint: AppTheme.primary)
                }
                .accessibilityIdentifier("settings-auto-lock-picker")

                Button {
                    passcodeFlow = .change
                } label: {
                    settingLabel("Change passcode", systemImage: "number", tint: AppTheme.primary)
                }
                .foregroundStyle(AppTheme.primaryDeep)

                Button {
                    passcodeFlow = .remove
                } label: {
                    Text("Turn off passcode")
                        .foregroundStyle(AppTheme.dangerText)
                }
            } else {
                Button {
                    passcodeFlow = .create
                } label: {
                    settingLabel("Set parent passcode", systemImage: "lock.fill", tint: AppTheme.primary)
                }
                .foregroundStyle(AppTheme.primaryDeep)
                .accessibilityIdentifier("settings-set-passcode-button")
            }
        } header: {
            Text("Security")
        } footer: {
            Text(lock.hasPasscode
                 ? "Kids can't change limits or stop timers without you."
                 : "Add a passcode so only you can change limits, stop timers or sign back in.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var childrenSection: some View {
        Section {
            if children.isEmpty {
                Text("No kids added yet")
                    .foregroundStyle(AppTheme.textSecondary)
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
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Kids")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var accountSection: some View {
        Section {
            Button {
                if lock.hasPasscode {
                    signOut()
                } else {
                    lockAfterPasscodeCreated = true
                    passcodeFlow = .create
                }
            } label: {
                Label("Lock BrightTime now", systemImage: "lock.fill")
                    .foregroundStyle(AppTheme.primary)
            }
            .accessibilityIdentifier("settings-lock-now-button")

            Button {
                isConfirmingSignOut = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(AppTheme.dangerText)
            }
            .accessibilityIdentifier("parent-sign-out-button")
        } header: {
            Text("Account")
        } footer: {
            Text("Your family's data stays on this iPhone when you sign out.")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: - Pieces

    private var timeSummary: String {
        _ = calendarRevision
        let zone = AppCalendar.isAutomatic ? "Automatic" : AppCalendar.city(of: AppCalendar.effectiveTimeZone)
        let reset = AppCalendar.dayResetHour == 0 ? "" : " · resets \(AppCalendar.resetHourLabel(AppCalendar.dayResetHour))"
        return zone + reset
    }

    private func settingLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { parent.notificationsEnabled },
            set: { newValue in
                parent.notificationsEnabled = newValue
                parent.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    /// Closes any open sheet first, then locks once it's gone.
    private func signOut() {
        isConfirmingSignOut = false
        passcodeFlow = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            onSignOut()
        }
    }
}

/// Edit the parent's name and photo. Pushed from the Profile tab.
struct EditParentProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let parent: ParentProfile

    @State private var name: String
    @State private var selectedAvatar: DefaultProfileAvatar
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?

    init(parent: ParentProfile) {
        self.parent = parent
        _name = State(initialValue: parent.name)
        _selectedAvatar = State(initialValue: parent.resolvedDefaultAvatar)
        _photoData = State(initialValue: parent.profilePhotoData)
    }

    private var isNameValid: Bool {
        ParentProfile.isValidName(name)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    avatar

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose profile photo", systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("settings-parent-photo-picker")

                        if photoData != nil {
                            Button("Use a default avatar") {
                                photoData = nil
                            }
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { _, newValue in
                        name = String(newValue.prefix(ParentProfile.maximumNameLength))
                    }

                if !name.isEmpty, !isNameValid {
                    Text("Enter a name between 2 and 16 characters.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.dangerText)
                }
            } header: {
                Text("Name & photo")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                DefaultAvatarPicker(
                    avatars: DefaultProfileAvatar.allCases,
                    selection: $selectedAvatar
                )
                .accessibilityIdentifier("settings-parent-default-avatar-picker")
            } header: {
                Text("Avatar")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                photoData = resizedPhotoData(data)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!isNameValid)
                .accessibilityIdentifier("save-parent-settings")
            }
        }
    }

    private var avatar: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(selectedAvatar.assetName).resizable().scaledToFill()
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(Circle())
        .overlay { Circle().stroke(AppTheme.cardBorder, lineWidth: 2) }
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
        parent.name = ParentProfile.normalizedName(name)
        parent.defaultAvatar = selectedAvatar
        parent.profilePhotoData = photoData
        parent.timeZoneIdentifier = AppCalendar.effectiveTimeZone.identifier
        parent.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}

