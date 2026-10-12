import Combine
import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Query(sort: \ParentProfile.createdAt) private var parentProfiles: [ParentProfile]
    @Query private var allChildren: [ChildProfile]
    @Query private var allDevices: [Device]
    @Query private var allSessions: [UsageSession]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLock.self) private var lock
    @Environment(FamilySync.self) private var familySync
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0
    @EnvironmentObject private var timerManager: ScreenTimerManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Hides the app while it's in the app switcher, so the dashboard never shows
    /// before the lock screen does.
    @State private var isObscured = false

    var body: some View {
        ZStack {
            if let parent = parentProfiles.first {
                // The app stays underneath the lock screen, so the current tab and
                // navigation survive an auto-lock.
                FamilyShellView(parent: parent) {
                    lock.lock(reason: .manual)
                }
                .allowsHitTesting(!lock.isLocked)
                .accessibilityHidden(lock.isLocked)

                if lock.isLocked {
                    LockScreenView(parent: parent)
                        .transition(.opacity)
                        .zIndex(1)
                }
            } else {
                ParentSetupView()
            }

            if isObscured && !lock.isLocked && lock.hasPasscode {
                PrivacyCover()
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .preferredColorScheme(appearance.colorScheme)
        .overlay {
            // One app-wide place that records finished timers, whichever screen
            // (or the lock screen) is showing.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Color.clear
                    .onChange(of: timeline.date) { _, now in
                        completeTimers(now: now)
                    }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: scenePhase) { _, phase in
            lock.handle(phase)
            isObscured = phase != .active
            switch phase {
            case .active:
                AppCalendar.apply()
                completeTimers(now: .now)
                familySync.sceneBecameActive()
            case .background:
                writeWidgetSnapshot()
                familySync.sceneWentToBackground()
            default:
                break
            }
        }
        .task {
            familySync.sceneBecameActive()
        }
        .onChange(of: widgetSignature, initial: true) { _, _ in
            writeWidgetSnapshot()
        }
        .onChange(of: allChildren.map(\.name)) { _, _ in
            BrightTimeShortcuts.updateAppShortcutParameters()
        }
        .onChange(of: parentProfiles.first?.id) { oldID, newID in
            // A brand-new parent was just set up. A passcode left in the Keychain
            // from an earlier install (Keychain items survive deleting the app)
            // would otherwise lock this family out with a code they never chose.
            guard oldID == nil, newID != nil,
                  let parent = parentProfiles.first,
                  Date.now.timeIntervalSince(parent.createdAt) < 120 else { return }
            lock.eraseAll()
            // Children synced from a co-parent before this parent was set up.
            familySync.adoptOrphans()
        }
        .onChange(of: lock.isLocked) { _, locked in
            if locked { Self.dismissPresentedScreens() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            AppCalendar.apply()
        }
    }

    /// Changes whenever something the widgets show changes.
    private var widgetSignature: String {
        let children = allChildren
            .map { "\($0.id)\($0.isActive)\($0.name)\($0.colorRawValue ?? "")\($0.limitMinutes(on: .now))\($0.bankBalance)" }
            .joined(separator: ",")
        let usage = allSessions.reduce(0) { $0 + $1.durationMinutes }
        let timers = timerManager.timers.map(\.id.uuidString).joined(separator: ",")
        return "\(children)|\(allSessions.count)|\(usage)|\(timers)|\(calendarRevision)"
    }

    private func writeWidgetSnapshot() {
        WidgetSnapshotWriter.write(children: allChildren, sessions: allSessions, timers: timerManager.timers)
    }

    private func completeTimers(now: Date) {
        timerManager.completeDueTimers(
            now: now,
            children: allChildren,
            devices: allDevices,
            context: modelContext
        )
    }

    /// Closes any open sheet or form when the app locks, so nothing stays usable
    /// above the lock screen.
    private static func dismissPresentedScreens() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.rootViewController?.presentedViewController != nil {
                window.rootViewController?.dismiss(animated: false)
            }
        }
    }
}

/// Plain brand screen shown in the app switcher while BrightTime is protected.
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            SunRingView(progress: 0.66, color: AppTheme.primary, rayColor: AppTheme.primary.opacity(0.55), size: 92, lineWidth: 7)
        }
        .accessibilityHidden(true)
    }
}

private struct FamilyShellView: View {
    @Query(sort: \ChildProfile.createdAt) private var children: [ChildProfile]
    @Query private var devices: [Device]
    @Query private var sessions: [UsageSession]

    let parent: ParentProfile
    let onSignOut: () -> Void

    @State private var destination: AnalysisDestination = .home
    @Namespace private var tabIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            Group {
                if destination == .home {
                    ContentView(parent: parent)
                } else if destination == .profile {
                    ParentSettingsView(parent: parent) {
                        // After signing back in, start from Home.
                        destination = .home
                        onSignOut()
                    }
                } else {
                    NavigationStack {
                        AnalysisView(
                            children: children.filter { $0.parent?.id == parent.id },
                            devices: devices,
                            sessions: sessions,
                            destination: destination
                        )
                    }
                }
            }
            .id(destination)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .animation(AppTheme.motion(reduceMotion: reduceMotion), value: destination)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .tint(AppTheme.primary)
        .sensoryFeedback(.selection, trigger: destination)
    }

    /// Floating capsule tab bar: the selected tab expands into a teal pill with its
    /// label and slides between positions; the others stay icon-only.
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AnalysisDestination.allCases) { item in
                let isSelected = destination == item

                Button {
                    withAnimation(AppTheme.motion(reduceMotion: reduceMotion)) {
                        destination = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: .semibold))

                        if isSelected {
                            Text(item.rawValue)
                                .font(.footnote.weight(.bold))
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.textTertiary)
                    .padding(.horizontal, isSelected ? 16 : 0)
                    .frame(maxWidth: isSelected ? nil : .infinity, minHeight: 48)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(AppTheme.accentGradient)
                                .matchedGeometryEffect(id: "tab-indicator", in: tabIndicator)
                                .shadow(color: AppTheme.primary.opacity(0.3), radius: 8, y: 4)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityIdentifier("analysis-\(item.rawValue.lowercased())-tab")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}
