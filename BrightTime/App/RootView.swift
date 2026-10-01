import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \ParentProfile.createdAt) private var parentProfiles: [ParentProfile]

    var body: some View {
        if let parent = parentProfiles.first {
            FamilyShellView(parent: parent)
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

    @State private var destination: AnalysisDestination = .home
    @Namespace private var tabIndicator

    var body: some View {
        Group {
            if destination != .home {
                NavigationStack {
                    AnalysisView(
                        children: children.filter { $0.parent?.id == parent.id },
                        devices: devices,
                        sessions: sessions,
                        destination: destination
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ContentView(parent: parent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: destination == .home)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            analysisNavigationBar
        }
        .tint(AppTheme.primary)
    }

    private var analysisNavigationBar: some View {
        HStack(spacing: 0) {
            ForEach(AnalysisDestination.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        destination = item
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(destination == item ? .white : AppTheme.textTertiary)
                            .frame(height: 25)

                        Text(item.rawValue)
                            .font(.caption2.weight(destination == item ? .bold : .medium))
                            .foregroundStyle(destination == item ? .white : AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        if destination == item {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.primary, AppTheme.lavender],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .matchedGeometryEffect(id: "tab-indicator", in: tabIndicator)
                                .shadow(color: AppTheme.primary.opacity(0.24), radius: 8, y: 4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("analysis-\(item.rawValue.lowercased())-tab")
                .accessibilityAddTraits(destination == item ? .isSelected : [])
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: AppTheme.primaryDeep.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}
