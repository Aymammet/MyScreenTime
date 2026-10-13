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
    @AppStorage(KidMode.storageKey) private var kidModeChildID = ""

    @State private var isShowingRecap = false
    @State private var isShowingRequests = false

    /// The kid this device is handed to, while kid mode is on.
    private var kidModeChild: ChildProfile? {
        guard !kidModeChildID.isEmpty else { return nil }
        return allChildren.first { $0.id.uuidString == kidModeChildID && $0.isActive }
    }

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
                .allowsHitTesting(!lock.isLocked && kidModeChild == nil)
                .accessibilityHidden(lock.isLocked || kidModeChild != nil)

                if let kid = kidModeChild {
                    // Kid mode replaces the lock screen: the kid only ever sees
                    // their own screen, and leaving it needs the parent.
                    KidModeView(child: kid)
                        .transition(.opacity)
                        .zIndex(1)
                } else if lock.isLocked {
                    LockScreenView(parent: parent)
                        .transition(.opacity)
                        .zIndex(1)
                }
            } else {
                ParentSetupView()
            }

            if isObscured && !lock.isLocked && lock.hasPasscode && kidModeChild == nil {
                PrivacyCover()
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .animation(.easeInOut(duration: 0.25), value: kidModeChildID)
        .sheet(isPresented: $isShowingRecap) {
            WeeklyRecapView()
        }
        .sheet(isPresented: $isShowingRequests) {
            RequestsSheet()
        }
        .onChange(of: AppRouter.shared.pending) { _, _ in
            openPendingRoute()
        }
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
                scheduleRecap()
            case .background:
                writeWidgetSnapshot()
                familySync.sceneWentToBackground()
            default:
                break
            }
        }
        .task {
            familySync.sceneBecameActive()
            scheduleRecap()
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
            if locked {
                Self.dismissPresentedScreens()
            } else {
                openPendingRoute()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            AppCalendar.apply()
        }
    }

    /// Opens the screen a notification tap asked for, once the parent can see it.
    private func openPendingRoute() {
        guard let destination = AppRouter.shared.pending,
              !lock.isLocked, kidModeChild == nil, parentProfiles.first != nil else { return }
        AppRouter.shared.pending = nil
        switch destination {
        case .recap: isShowingRecap = true
        case .requests: isShowingRequests = true
        }
    }

    private func scheduleRecap() {
        guard let parent = parentProfiles.first else { return }
        let names = allChildren
            .filter { $0.isActive && $0.parent?.id == parent.id }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.name)
        AppNotifications.shared.rescheduleRecap(kidNames: names, notificationsOn: parent.notificationsEnabled)
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

/// Opened from a time-request notification.
private struct RequestsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PendingRequestsCard()
                    Text("Answered requests disappear from this list.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Time requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
    /// Goes up when the parent taps the tab that's already open: the tab
    /// goes back to its first screen and scrolls to the top.
    @State private var reselectCount = 0
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
            .environment(\.tabReselectCount, reselectCount)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .animation(AppTheme.motion(reduceMotion: reduceMotion), value: destination)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .tint(AppTheme.primary)
        .sensoryFeedback(.selection, trigger: destination)
        .sensoryFeedback(.impact(weight: .light), trigger: reselectCount)
    }

    /// Floating capsule tab bar: the selected tab expands into a teal pill with its
    /// label and slides between positions; the others stay icon-only.
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AnalysisDestination.allCases) { item in
                let isSelected = destination == item

                Button {
                    if isSelected {
                        reselectCount += 1
                    } else {
                        withAnimation(AppTheme.motion(reduceMotion: reduceMotion)) {
                            destination = item
                        }
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

// MARK: - Tapping the open tab again

private struct TabReselectKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Goes up by one each time the parent taps the tab that's already open.
    var tabReselectCount: Int {
        get { self[TabReselectKey.self] }
        set { self[TabReselectKey.self] = newValue }
    }
}

enum ScrollTopAnchor {
    static let id = "brighttime.scroll-top"
}

extension View {
    /// Marks the top of a tab's scrolling content. Goes on the content inside the ScrollView.
    func scrollTopAnchor() -> some View {
        background(alignment: .top) {
            Color.clear
                .frame(height: 1)
                .id(ScrollTopAnchor.id)
        }
    }

    /// Scrolls back to `scrollTopAnchor()` when the open tab is tapped again.
    func scrollsToTopOnTabReselect() -> some View {
        modifier(ScrollToTopOnTabReselect())
    }

    /// Same, for a Form or List (scroll positions don't apply to those).
    /// Goes all the way up, so a collapsed large title opens again.
    func scrollsFormToTopOnTabReselect() -> some View {
        modifier(FormScrollToTop())
    }

    /// Closes a pushed screen when its tab is tapped again, like iPhone apps do.
    func popsToRootOnTabReselect() -> some View {
        modifier(PopToRootOnTabReselect())
    }
}

private struct ScrollToTopOnTabReselect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(EdgeScrollToTop())
        } else {
            content.modifier(AnchorScrollToTop())
        }
    }
}

/// iOS 18+: scrolls to the very top edge, so a large title opens back up.
@available(iOS 18.0, *)
private struct EdgeScrollToTop: ViewModifier {
    @Environment(\.tabReselectCount) private var reselectCount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: reselectCount) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                    position.scrollTo(edge: .top)
                }
            }
    }
}

/// iOS 17: scrolls to the `scrollTopAnchor()` marker.
private struct AnchorScrollToTop: ViewModifier {
    @Environment(\.tabReselectCount) private var reselectCount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: reselectCount) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                    proxy.scrollTo(ScrollTopAnchor.id, anchor: .top)
                }
            }
        }
    }
}

private struct FormScrollToTop: ViewModifier {
    @Environment(\.tabReselectCount) private var reselectCount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background {
            FormScrollToTopBridge(trigger: reselectCount, animated: !reduceMotion)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// Finds the scroll view UIKit uses for a Form and scrolls it to the top edge.
private struct FormScrollToTopBridge: UIViewRepresentable {
    let trigger: Int
    let animated: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        guard let scrollView = Self.nearestScrollView(around: view) else { return }
        let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
        scrollView.setContentOffset(top, animated: animated)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastTrigger: trigger)
    }

    final class Coordinator {
        var lastTrigger: Int
        init(lastTrigger: Int) { self.lastTrigger = lastTrigger }
    }

    /// Walks up from the marker and returns the first scroll view found below each ancestor.
    private static func nearestScrollView(around view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let found = firstScrollView(in: current) { return found }
            ancestor = current.superview
        }
        return nil
    }

    private static func firstScrollView(in root: UIView) -> UIScrollView? {
        var queue = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scrollView = next as? UIScrollView, scrollView.isScrollEnabled { return scrollView }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }
}

private struct PopToRootOnTabReselect: ViewModifier {
    @Environment(\.tabReselectCount) private var reselectCount
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onChange(of: reselectCount) {
            dismiss()
        }
    }
}
