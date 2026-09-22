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
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(destination == item ? AppTheme.primary : Color.clear)
                            .frame(width: 34, height: 3)

                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(destination == item ? .white : .secondary)
                            .frame(width: 38, height: 38)
                            .background {
                                if destination == item {
                                    Circle()
                                        .fill(AppTheme.primary)
                                        .matchedGeometryEffect(id: "tab-indicator", in: tabIndicator)
                                }
                            }

                        Text(item.rawValue)
                            .font(.caption2.weight(destination == item ? .semibold : .medium))
                            .foregroundStyle(destination == item ? AppTheme.primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("analysis-\(item.rawValue.lowercased())-tab")
                .accessibilityAddTraits(destination == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 7)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}
