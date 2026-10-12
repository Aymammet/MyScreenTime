import SwiftData
import SwiftUI

// MARK: - Kid screen

/// What a kid sees when a parent hands them this iPhone or iPad: their time left,
/// their time bank, and a way to ask for more. Nothing else in BrightTime is
/// reachable until a parent unlocks it.
struct KidModeView: View {
    let child: ChildProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(AppLock.self) private var lock
    @EnvironmentObject private var timerManager: ScreenTimerManager
    @Query private var sessions: [UsageSession]
    @Query private var devices: [Device]
    @Query private var children: [ChildProfile]
    @Query(sort: \TimeRequest.updatedAt, order: .reverse) private var requests: [TimeRequest]
    @AppStorage(KidMode.storageKey) private var kidModeChildID = ""

    @State private var parentAction: ParentAction?
    @State private var askedMinutes = 15

    private enum ParentAction: Identifiable {
        case exit
        case approve(TimeRequest)

        var id: String {
            switch self {
            case .exit: "exit"
            case .approve(let request): request.id.uuidString
            }
        }

        var isExit: Bool {
            if case .exit = self { return true }
            return false
        }
    }

    private var today: Date { .now }

    private var pendingRequest: TimeRequest? {
        let calendar = AppCalendar.day
        return requests.first {
            $0.childID == child.id && $0.status == .pending && calendar.isDate($0.day, inSameDayAs: today)
        }
    }

    private var latestAnswer: TimeRequest? {
        let calendar = AppCalendar.day
        return requests.first {
            $0.childID == child.id && $0.status != .pending && calendar.isDate($0.day, inSameDayAs: today)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let now = timeline.date
            let timer = timerManager.timer(for: child.id)
            let summary = UsageAggregator.summary(on: now, child: child, sessions: sessions)
            let running = timer.map { max(Int(min(now, $0.endsAt).timeIntervalSince($0.startedAt) / 60), 0) } ?? 0
            let used = summary.usedMinutes + running
            let limit = summary.limitMinutes
            let left = max(limit - used, 0)

            ScrollView {
                VStack(spacing: 14) {
                    header
                    timeLeftCard(left: left, used: used, limit: limit)
                    if let timer {
                        timerCard(timer)
                    }
                    askCard
                    bankCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .sheet(item: $parentAction) { action in
            ParentGateSheet(
                title: action.isExit ? "Leave kid mode" : "Approve extra time",
                message: action.isExit ? "Enter the parent passcode to go back to BrightTime." : "Enter the parent passcode to say yes."
            ) {
                switch action {
                case .exit:
                    kidModeChildID = ""
                    lock.unlock()
                case .approve(let request):
                    KidRequests.approve(request, context: modelContext)
                }
            }
        }
        .animation(AppTheme.spring, value: pendingRequest?.id)
        .animation(AppTheme.spring, value: latestAnswer?.id)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            ChildAvatarView(child: child, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hi, \(child.name)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                parentAction = .exit
            } label: {
                Label("Parent", systemImage: "lock.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kid-mode-parent-button")
        }
        .padding(.top, 8)
    }

    private func timeLeftCard(left: Int, used: Int, limit: Int) -> some View {
        let progress = limit > 0 ? Double(used) / Double(limit) : 0
        let isOver = used > limit
        return VStack(spacing: 14) {
            SunRingView(
                progress: progress,
                color: isOver ? AppTheme.danger : child.color.color,
                size: 190,
                lineWidth: 14
            ) {
                VStack(spacing: 2) {
                    Text(isOver ? TimeText.compact(used - limit) : TimeText.compact(left))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .contentTransition(.numericText())
                    Text(isOver ? "over today" : "left today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Text("\(TimeText.compact(used)) used of \(TimeText.compact(limit))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .brightCard(padding: 22)
        .accessibilityElement(children: .combine)
    }

    private func timerCard(_ timer: ActiveScreenTimer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 40, height: 40)
                .background(AppTheme.primaryTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.deviceName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryDeep)
                Text(timerInterval: Date.now...max(timer.endsAt, .now), countsDown: true)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                timerManager.stop(timer, children: children, devices: devices, context: modelContext)
            } label: {
                Label("I'm done", systemImage: "stop.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.onPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .brightCard()
    }

    @ViewBuilder
    private var askCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = pendingRequest {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Asked for +\(TimeText.compact(pending.minutes))")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text("Waiting for a parent to answer.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        parentAction = .approve(pending)
                    } label: {
                        Text("Parent: approve here")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(AppTheme.primary, in: Capsule())
                    }
                    .accessibilityIdentifier("kid-mode-approve-here")
                    Button {
                        KidRequests.cancel(pending, context: modelContext)
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.primaryDeep)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(AppTheme.surfaceMuted, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            } else {
                if let answer = latestAnswer {
                    Label(
                        answer.status == .approved
                            ? "A parent said yes: +\(TimeText.compact(answer.minutes)) added today"
                            : "Not this time. You can ask again later.",
                        systemImage: answer.status == .approved ? "checkmark.seal.fill" : "hand.raised.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(answer.status == .approved ? AppTheme.primary : AppTheme.warningText)
                }
                Text("Need more time?")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryDeep)
                HStack(spacing: 10) {
                    ForEach(KidRequests.choices, id: \.self) { minutes in
                        Button {
                            KidRequests.ask(child: child, minutes: minutes, context: modelContext)
                        } label: {
                            Text("+\(TimeText.compact(minutes))")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.primaryDeep)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.primaryTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppTheme.primary.opacity(0.4), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("kid-mode-ask-\(minutes)")
                    }
                }
                Text("A parent gets your request and can say yes from their phone.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brightCard()
    }

    private var bankCard: some View {
        let balance = child.bankBalance
        return HStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(TimeText.compact(balance)) in your bank")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryDeep)
                Text(balance >= 15 ? "Time you earned. Use it whenever you like." : "Earn time with reading, chores and more.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 0)
            if balance >= 15 {
                Button {
                    useBankedTime(15)
                } label: {
                    Text("Use 15m")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.warningTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("kid-mode-use-bank")
            }
        }
        .brightCard()
    }

    private func useBankedTime(_ minutes: Int) {
        guard child.bankBalance >= minutes else { return }
        modelContext.insert(TimeCredit(kind: .used, minutes: minutes, title: "Used from the bank", symbol: "star.fill", day: .now, child: child))
        try? modelContext.save()
    }
}

// MARK: - Parent check

/// Asks for the parent passcode (or Face ID) and runs `onVerified` when it's right.
struct ParentGateSheet: View {
    let title: String
    let message: String
    let onVerified: () -> Void

    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 12)
                PasscodePad(
                    title: title,
                    message: message,
                    biometry: lock.canUseBiometrics ? lock.biometry : .none,
                    onBiometric: lock.canUseBiometrics ? {
                        Task {
                            if await lock.verifyWithBiometrics() { finish() }
                        }
                    } : nil
                ) { code in
                    switch lock.check(code) {
                    case .correct:
                        finish()
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func finish() {
        onVerified()
        dismiss()
    }
}

// MARK: - Starting kid mode (parent side)

/// Profile → Kid mode: pick a kid and hand them this iPhone or iPad.
struct KidModeSetupView: View {
    let parent: ParentProfile

    @Environment(AppLock.self) private var lock
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]
    @AppStorage(KidMode.storageKey) private var kidModeChildID = ""
    @State private var selectedID: UUID?
    @State private var isSettingPasscode = false

    private var children: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id && $0.isActive }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Hand this iPhone or iPad to a kid", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryDeep)
                    Text("They'll see only their time left, their time bank and an \"Ask for more time\" button. Getting back to BrightTime needs your passcode or Face ID.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(AppTheme.surface)

            Section {
                if children.isEmpty {
                    Text("Add a kid first.")
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(children) { child in
                        Button {
                            selectedID = child.id
                        } label: {
                            HStack(spacing: 12) {
                                ChildAvatarView(child: child, size: 36)
                                Text(child.name)
                                    .foregroundStyle(AppTheme.primaryDeep)
                                Spacer()
                                if selectedID == child.id {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(AppTheme.primary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Who's using this device?")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                Button {
                    start()
                } label: {
                    Text(lock.hasPasscode ? "Start kid mode" : "Set a passcode and start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(selectedID == nil)
                .accessibilityIdentifier("kid-mode-start")
            } footer: {
                Text("With co-parent sharing on, requests also reach the other parent's iPhone.")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Kid mode")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedID = selectedID ?? children.first?.id }
        .sheet(isPresented: $isSettingPasscode) {
            PasscodeSetupView(mode: .create) { completed in
                if completed { start() }
            }
        }
    }

    private func start() {
        guard let selectedID else { return }
        guard lock.hasPasscode else {
            isSettingPasscode = true
            return
        }
        kidModeChildID = selectedID.uuidString
        Task { await AppNotifications.shared.requestAuthorizationIfNeeded() }
    }
}

// MARK: - Requests on the parent's Home

/// Shown at the top of Home when a kid is waiting for an answer.
struct PendingRequestsCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeRequest.createdAt) private var requests: [TimeRequest]
    @Query private var children: [ChildProfile]

    private var pending: [TimeRequest] {
        let calendar = AppCalendar.day
        return requests.filter { $0.status == .pending && calendar.isDate($0.day, inSameDayAs: .now) }
    }

    var body: some View {
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(title: pending.count == 1 ? "Time request" : "Time requests", detail: "\(pending.count) waiting")
                ForEach(pending) { request in
                    row(request)
                }
            }
            .brightCard()
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.warning.opacity(0.55), lineWidth: 1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func row(_ request: TimeRequest) -> some View {
        let child = children.first { $0.id == request.childID }
        return HStack(spacing: 10) {
            if let child {
                ChildAvatarView(child: child, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(child?.name ?? "A kid") asks for +\(TimeText.compact(request.minutes))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryDeep)
                Text(request.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Not now") {
                withAnimation(AppTheme.spring) { KidRequests.deny(request, context: modelContext) }
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityIdentifier("request-deny")
            Button {
                withAnimation(AppTheme.spring) { KidRequests.approve(request, context: modelContext) }
            } label: {
                Text("Approve")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.onPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary, in: Capsule())
            }
            .accessibilityIdentifier("request-approve")
        }
        .buttonStyle(.plain)
    }
}
