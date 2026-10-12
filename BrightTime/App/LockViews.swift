import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Passcode pad

/// A 4-digit passcode keypad. `onComplete` returns an error message to reject the
/// entry (the dots shake and clear), or nil to accept it.
struct PasscodePad: View {
    let title: String
    var message: String?
    var biometry: AppLock.Biometry = .none
    var onBiometric: (() -> Void)?
    let onComplete: (String) -> String?

    @State private var entry = ""
    @State private var error: String?
    @State private var errorCount = 0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.primaryDeep)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 18) {
                ForEach(0..<AppLock.passcodeLength, id: \.self) { index in
                    Circle()
                        .fill(index < entry.count ? AppTheme.primary : Color.clear)
                        .overlay { Circle().stroke(AppTheme.primary, lineWidth: 1.5) }
                        .frame(width: 14, height: 14)
                }
            }
            .phaseAnimator([0.0, -12.0, 12.0, -7.0, 7.0, 0.0], trigger: errorCount) { content, offset in
                content.offset(x: offset)
            } animation: { _ in
                .linear(duration: 0.06)
            }
            .accessibilityElement()
            .accessibilityLabel("\(entry.count) of \(AppLock.passcodeLength) digits entered")

            Text(error ?? " ")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.dangerText)
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 22), count: 3), spacing: 16) {
                ForEach(keys, id: \.self) { key in
                    digitButton(key)
                }

                if let onBiometric, biometry != .none {
                    Button(action: onBiometric) {
                        Image(systemName: biometry.systemImage)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 72, height: 72)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(biometry.name)")
                } else {
                    Color.clear.frame(width: 72, height: 72)
                }

                digitButton("0")

                Button {
                    if !entry.isEmpty { entry.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
        }
        .sensoryFeedback(.error, trigger: errorCount)
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            press(digit)
        } label: {
            Text(digit)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.primaryDeep)
                .frame(width: 72, height: 72)
                .background(AppTheme.surface, in: Circle())
                .overlay { Circle().stroke(AppTheme.cardBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: entry)
        .accessibilityIdentifier("passcode-key-\(digit)")
    }

    private func press(_ digit: String) {
        guard entry.count < AppLock.passcodeLength else { return }
        entry.append(digit)
        error = nil
        guard entry.count == AppLock.passcodeLength else { return }

        let submitted = entry
        if let message = onComplete(submitted) {
            error = message
            errorCount += 1
        }
        entry = ""
    }
}

// MARK: - Set up / change / remove passcode

struct PasscodeSetupView: View {
    enum Mode {
        case create, change, remove
    }

    let mode: Mode
    var onFinished: (Bool) -> Void = { _ in }

    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case verifyCurrent
        case enterNew
        case confirmNew(String)
    }

    @State private var step: Step

    init(mode: Mode, onFinished: @escaping (Bool) -> Void = { _ in }) {
        self.mode = mode
        self.onFinished = onFinished
        _step = State(initialValue: mode == .create ? .enterNew : .verifyCurrent)
    }

    private var title: String {
        switch step {
        case .verifyCurrent: "Enter your current passcode"
        case .enterNew: mode == .create ? "Create a parent passcode" : "Enter a new passcode"
        case .confirmNew: "Confirm your passcode"
        }
    }

    private var message: String? {
        switch step {
        case .verifyCurrent: mode == .remove ? "Turning off the passcode also turns off Face ID and auto-lock." : nil
        case .enterNew: "Only you will be able to change limits or stop timers."
        case .confirmNew: "Enter the same 4 digits again."
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 12)
                PasscodePad(title: title, message: message) { code in
                    handle(code)
                }
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(mode == .remove ? "Turn Off Passcode" : "Parent Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onFinished(false)
                    }
                }
            }
        }
    }

    private func handle(_ code: String) -> String? {
        switch step {
        case .verifyCurrent:
            switch lock.check(code) {
            case .correct:
                if mode == .remove {
                    lock.removePasscode()
                    finish()
                } else {
                    step = .enterNew
                }
                return nil
            case .wrong(let attemptsLeft):
                return "Wrong passcode. \(attemptsLeft) \(attemptsLeft == 1 ? "try" : "tries") left."
            case .coolingDown(let until):
                return Self.cooldownMessage(until: until)
            }
        case .enterNew:
            step = .confirmNew(code)
            return nil
        case .confirmNew(let first):
            guard code == first else {
                step = .enterNew
                return "Passcodes didn't match. Try again."
            }
            guard lock.setPasscode(code) else {
                step = .enterNew
                return "Couldn't save the passcode. Please try again."
            }
            finish()
            return nil
        }
    }

    private func finish() {
        dismiss()
        onFinished(true)
    }

    static func cooldownMessage(until: Date) -> String {
        let minutes = max(Int(ceil(until.timeIntervalSinceNow / 60)), 1)
        return "Too many tries. Try again in \(minutes) min."
    }
}

// MARK: - Unlock with passcode

struct PasscodeUnlockSheet: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 12)
                PasscodePad(
                    title: "Enter parent passcode",
                    message: nil,
                    biometry: lock.canUseBiometrics ? lock.biometry : .none,
                    onBiometric: lock.canUseBiometrics ? {
                        Task {
                            if await lock.unlockWithBiometrics() { dismiss() }
                        }
                    } : nil
                ) { code in
                    switch lock.check(code) {
                    case .correct:
                        lock.unlock()
                        dismiss()
                        return nil
                    case .wrong(let attemptsLeft):
                        return "Wrong passcode. \(attemptsLeft) \(attemptsLeft == 1 ? "try" : "tries") left."
                    case .coolingDown(let until):
                        return PasscodeSetupView.cooldownMessage(until: until)
                    }
                }
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Unlock BrightTime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Locked screen

/// Shown instead of the app while it's locked (after Sign Out or auto-lock). Kids'
/// status is visible at a glance; changing anything needs the parent.
struct LockScreenView: View {
    let parent: ParentProfile

    @Environment(AppLock.self) private var lock
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]
    @Query private var sessions: [UsageSession]
    @EnvironmentObject private var timerManager: ScreenTimerManager

    @State private var isShowingPasscode = false
    @State private var isShowingReset = false
    @State private var biometryNotice: String?

    private var children: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id && $0.isActive }
    }

    private var lockedMessage: String {
        guard lock.hasPasscode else {
            return "You're signed out. Your family's data is still on this iPhone."
        }
        return lock.offersBiometrics
            ? "Unlock with \(lock.biometry.name) or your parent passcode to change limits or stop a timer."
            : "Unlock with your parent passcode to change limits or stop a timer."
    }

    private func unlockWithBiometrics() {
        guard lock.isBiometryEnrolled else {
            biometryNotice = "\(lock.biometry.name) isn't set up on this iPhone. Use your passcode, or turn on \(lock.biometry.name) in iPhone Settings."
            isShowingPasscode = true
            return
        }
        Task {
            let unlocked = await lock.unlockWithBiometrics()
            if !unlocked { isShowingPasscode = true }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                SunRingView(progress: 0.66, color: AppTheme.primary, rayColor: AppTheme.primary.opacity(0.55), size: 92, lineWidth: 7) {
                    ZStack {
                        Capsule().fill(AppTheme.primaryDeep).frame(width: 5, height: 17).offset(y: -6)
                        Capsule().fill(AppTheme.primaryDeep).frame(width: 15, height: 5).offset(x: 5)
                    }
                }

                Text("Welcome back, \(parent.name)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)

                Text(lockedMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 30)

                if !children.isEmpty {
                    kidStatus
                        .padding(.top, 24)
                }

                Spacer(minLength: 24)

                actions
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $isShowingPasscode) {
            PasscodeUnlockSheet()
        }
        .sheet(isPresented: $isShowingReset) {
            ResetBrightTimeView()
        }
        .task {
            // Only after an automatic lock. After Sign Out, the parent's own face
            // would otherwise unlock the app again straight away.
            if lock.shouldAutoPromptBiometrics {
                await lock.unlockWithBiometrics()
            }
        }
    }

    private var kidStatus: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { kidPills }
                VStack(spacing: 8) { kidPills }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var kidPills: some View {
        ForEach(children) { child in
            let summary = UsageAggregator.summary(on: .now, child: child, sessions: sessions)
            let hasTimer = timerManager.timer(for: child.id) != nil

            HStack(spacing: 6) {
                Circle().fill(child.color.color).frame(width: 8, height: 8)
                Text(child.name).fontWeight(.bold)
                Text("·").foregroundStyle(AppTheme.textTertiary)
                if hasTimer {
                    Label("timer on", systemImage: "timer").labelStyle(.titleAndIcon)
                } else {
                    Text(summary.overMinutes > 0
                         ? "\(TimeText.compact(summary.overMinutes)) over"
                         : "\(TimeText.compact(summary.remainingMinutes)) left")
                }
            }
            .font(.caption)
            .foregroundStyle(hasTimer ? AppTheme.primary : AppTheme.statusTextColor(for: summary.status))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(AppTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(AppTheme.cardBorder, lineWidth: 1) }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if lock.hasPasscode {
                if lock.offersBiometrics {
                    Button {
                        unlockWithBiometrics()
                    } label: {
                        Label("Unlock with \(lock.biometry.name)", systemImage: lock.biometry.systemImage)
                            .font(.headline)
                            .foregroundStyle(AppTheme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(AppTheme.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("unlock-biometrics-button")

                    Button {
                        isShowingPasscode = true
                    } label: {
                        Label("Use Passcode", systemImage: "circle.grid.3x3.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(AppTheme.primaryTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("unlock-passcode-button")

                    if let biometryNotice {
                        Text(biometryNotice)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                } else {
                    Button {
                        isShowingPasscode = true
                    } label: {
                        Label("Unlock with Passcode", systemImage: "lock.open.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(AppTheme.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("unlock-passcode-button")
                }
            } else {
                Button {
                    lock.unlock()
                } label: {
                    Text("Continue as \(parent.name)")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("parent-sign-back-in-button")
            }

            Button("Not \(parent.name)? Reset BrightTime…") { isShowingReset = true }
                .font(.footnote)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Sign out confirmation

struct SignOutSheet: View {
    let onSignOut: () -> Void

    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingPasscode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign out of BrightTime?")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.primaryDeep)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text("Here's what happens:")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)

            bullet("timer", title: "Timers keep running.", detail: "You still get \u{201C}time's up\u{201D} notifications.")
            bullet("lock.fill", title: "Limits are locked.", detail: "Nobody can change them until you unlock.")
            bullet("iphone", title: "Your family's data stays", detail: "on this iPhone. Nothing is deleted.")

            if !lock.hasPasscode {
                Text("First, set a parent passcode so only you can unlock BrightTime.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.warningText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.warningTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 8) {
                Button {
                    if lock.hasPasscode {
                        confirm()
                    } else {
                        isCreatingPasscode = true
                    }
                } label: {
                    Text(lock.hasPasscode ? "Sign Out" : "Set Passcode & Sign Out")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.danger, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirm-sign-out-button")

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.surfaceMuted, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .presentationDetents([.height(lock.hasPasscode ? 430 : 500)])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.surface)
        .sheet(isPresented: $isCreatingPasscode) {
            PasscodeSetupView(mode: .create) { created in
                if created { confirm() }
            }
        }
    }

    private func confirm() {
        dismiss()
        onSignOut()
    }

    private func bullet(_ icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 30, height: 30)
                .background(AppTheme.primaryTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("\(Text(title).bold()) \(detail)")
                .font(.subheadline)
                .foregroundStyle(AppTheme.primaryDeep)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reset

/// Erases everything (profiles, devices, history, passcode) after a typed confirmation.
struct ResetBrightTimeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLock.self) private var lock
    @EnvironmentObject private var timerManager: ScreenTimerManager

    @State private var confirmation = ""
    /// With a passcode set, the parent must prove it's them before erasing, so a
    /// child can't wipe BrightTime (and its limits) from the lock screen.
    @State private var isParentVerified = false

    private var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).uppercased() == "RESET"
    }

    var body: some View {
        NavigationStack {
            Group {
                if lock.hasPasscode && !isParentVerified {
                    verification
                } else {
                    resetForm
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Reset BrightTime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var verification: some View {
        VStack {
            Spacer(minLength: 12)
            PasscodePad(
                title: "Parent passcode required",
                message: "Only the parent can erase BrightTime.",
                biometry: lock.canUseBiometrics ? lock.biometry : .none,
                onBiometric: lock.canUseBiometrics ? {
                    Task {
                        if await lock.verifyWithBiometrics() { isParentVerified = true }
                    }
                } : nil
            ) { code in
                switch lock.check(code) {
                case .correct:
                    isParentVerified = true
                    return nil
                case .wrong(let attemptsLeft):
                    return "Wrong passcode. \(attemptsLeft) \(attemptsLeft == 1 ? "try" : "tries") left."
                case .coolingDown(let until):
                    return PasscodeSetupView.cooldownMessage(until: until)
                }
            }
            Text("Forgot your passcode? Delete BrightTime from this iPhone and install it again to start over. This erases its data.")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 8)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var resetForm: some View {
            Form {
                Section {
                    Label("This deletes every profile, device and usage record on this iPhone, and removes the parent passcode. It can't be undone.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.dangerText)
                }
                .listRowBackground(AppTheme.dangerTint)

                Section {
                    TextField("Type RESET to confirm", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("reset-confirmation-field")
                } footer: {
                    Text("Use this if you're setting BrightTime up for a different parent.")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Button("Erase Everything", role: .destructive) {
                        eraseEverything()
                    }
                    .disabled(!isConfirmed)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("reset-erase-button")
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
    }

    private func eraseEverything() {
        // Disconnect first, so erasing this iPhone never deletes the shared family.
        FamilySync.shared.disconnectForReset()
        wipe(TimeCredit.self)
        wipe(EarnActivity.self)
        wipe(UsageSession.self)
        wipe(Device.self)
        wipe(ChildProfile.self)
        wipe(ParentProfile.self)
        try? modelContext.save()

        timerManager.clearAll()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        lock.eraseAll()
        UserDefaults.standard.removeObject(forKey: "brighttime.bank.seeded")
        dismiss()
    }

    private func wipe<Model: PersistentModel>(_ type: Model.Type) {
        guard let items = try? modelContext.fetch(FetchDescriptor<Model>()) else { return }
        for item in items {
            modelContext.delete(item)
        }
    }
}
