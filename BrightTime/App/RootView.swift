import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \ParentProfile.createdAt) private var parentProfiles: [ParentProfile]
    @AppStorage("brighttime.parentIsSignedOut") private var isSignedOut = false

    private var isUITesting: Bool {
        CommandLine.arguments.contains("-ui-testing")
    }

    var body: some View {
        if let parent = parentProfiles.first {
            if isSignedOut && !isUITesting {
                SignedOutView(parent: parent) {
                    isSignedOut = false
                }
            } else {
                FamilyShellView(parent: parent) {
                    isSignedOut = true
                }
            }
        } else {
            ParentSetupView()
        }
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
                    ContentView(parent: parent, onSignOut: onSignOut)
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
                    .foregroundStyle(isSelected ? Color.white : AppTheme.textTertiary)
                    .padding(.horizontal, isSelected ? 16 : 0)
                    .frame(maxWidth: isSelected ? nil : .infinity, minHeight: 48)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(AppTheme.heroGradient)
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

private struct SignedOutView: View {
    let parent: ParentProfile
    let signBackIn: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.background, AppTheme.primaryTint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                SunRingView(progress: 0.66, color: AppTheme.primary, size: 64, lineWidth: 6)

                Text("BrightTime")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryDeep)

                ParentAvatarView(parent: parent, size: 92)

                VStack(spacing: 5) {
                    Text("Signed out")
                        .font(.title2.bold())
                    Text("Your family data remains on this device.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Button {
                    signBackIn()
                } label: {
                    Label("Continue as \(parent.name)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .accessibilityIdentifier("parent-sign-back-in-button")
            }
            .padding(28)
            .frame(maxWidth: 430)
        }
    }
}
