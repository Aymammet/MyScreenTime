import SwiftUI

/// Settings → Co-parents: invite a partner or grandparent through iCloud, see who
/// has joined, and stop sharing or leave.
struct FamilySharingView: View {
    @Environment(FamilySync.self) private var sync
    @State private var isConfirmingLeave = false

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            switch sync.role {
            case .none: inviteSection
            case .owner: ownerSections
            case .member: memberSections
            }

            if case .failed(let message) = sync.status {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.dangerText)
                }
                .listRowBackground(AppTheme.dangerTint)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Co-parents")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sync.refreshParticipants()
        }
        .refreshable {
            await sync.syncNow()
        }
        .confirmationDialog(
            sync.role == .owner ? "Stop sharing your family?" : "Leave this family?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button(sync.role == .owner ? "Stop Sharing" : "Leave Family", role: .destructive) {
                Task { await sync.leaveFamily() }
            }
        } message: {
            Text(sync.role == .owner
                 ? "Co-parents lose access and stop seeing updates. Everything stays on your iPhone."
                 : "You'll stop getting updates. What's already on this iPhone stays here.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryTint)
                    .frame(width: 76, height: 76)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }
            Text(headline)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.primaryDeep)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                benefit("Same kids, devices and history on both iPhones", systemImage: "arrow.triangle.2.circlepath")
                benefit("Limits and the time bank stay in sync", systemImage: "star.circle")
                benefit("Each parent keeps their own passcode", systemImage: "lock")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var headline: String {
        switch sync.role {
        case .none: "Share BrightTime with a co-parent"
        case .owner: "You're sharing your family"
        case .member: sync.ownerName.map { "You're in \($0)'s family" } ?? "You're in a shared family"
        }
    }

    private func benefit(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.primary)
        }
    }

    // MARK: - Not sharing

    private var inviteSection: some View {
        Section {
            Button {
                Task { await sync.inviteCoParent() }
            } label: {
                HStack {
                    Spacer()
                    if sync.isWorking {
                        ProgressView().tint(AppTheme.onPrimary)
                    }
                    Text(workingText ?? "Invite a co-parent")
                        .font(.headline)
                    Spacer()
                }
                .foregroundStyle(AppTheme.onPrimary)
                .padding(.vertical, 14)
                .background(AppTheme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sync.isWorking)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .accessibilityIdentifier("invite-co-parent-button")
        } footer: {
            Text("Send the invite by Messages or Mail. Your co-parent opens it on their iPhone with BrightTime installed. Both of you need to be signed in to iCloud.\n\nGot an invite? Open the link on this iPhone.")
        }
    }

    // MARK: - Owner

    @ViewBuilder
    private var ownerSections: some View {
        Section {
            ForEach(sync.participants) { person in
                HStack(spacing: 12) {
                    Image(systemName: person.isOwner ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.isOwner ? "\(person.name) (you)" : person.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text(person.isOwner ? "Organizer" : (person.isAccepted ? "Joined" : "Invited, not joined yet"))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            Button {
                Task { await sync.manageParticipants() }
            } label: {
                Label("Invite or remove people", systemImage: "person.badge.plus")
            }
            .foregroundStyle(AppTheme.primary)
        } header: {
            Text("People")
        }
        .listRowBackground(AppTheme.surface)

        syncSection

        Section {
            Button("Stop sharing", role: .destructive) {
                isConfirmingLeave = true
            }
            .foregroundStyle(AppTheme.dangerText)
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: - Member

    @ViewBuilder
    private var memberSections: some View {
        syncSection

        Section {
            Button("Leave family", role: .destructive) {
                isConfirmingLeave = true
            }
            .foregroundStyle(AppTheme.dangerText)
        } footer: {
            Text("Running timers show on the iPhone that started them. Their time is shared when they finish.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var syncSection: some View {
        Section {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                if sync.isWorking {
                    ProgressView()
                } else {
                    Button("Sync now") {
                        Task { await sync.syncNow() }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.primary)
                }
            }
        } header: {
            Text("iCloud")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var workingText: String? {
        if case .working(let text) = sync.status { return text }
        return nil
    }

    private var statusText: String {
        switch sync.status {
        case .idle: "Ready"
        case .working(let text): text
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))"
        case .failed: "Couldn't sync"
        }
    }

    private var statusIcon: String {
        switch sync.status {
        case .failed: "exclamationmark.icloud"
        case .working: "arrow.triangle.2.circlepath.icloud"
        default: "checkmark.icloud"
        }
    }
}
