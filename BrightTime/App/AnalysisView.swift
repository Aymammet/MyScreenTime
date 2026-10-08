import SwiftData
import SwiftUI

enum AnalysisDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case devices = "Devices"
    case children = "Children"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .weekly: "chart.bar.fill"
        case .monthly: "calendar"
        case .devices: "ipad.and.iphone"
        case .children: "person.2.fill"
        }
    }
}

/// Routes the non-Home tabs to their screens. Each tab owns its own state and
/// layout; this view only supplies the shared chrome (title, background, tint).
struct AnalysisView: View {
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]
    let destination: AnalysisDestination

    private var activeChildren: [ChildProfile] {
        children.filter(\.isActive)
    }

    var body: some View {
        content
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(destination.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .tint(AppTheme.primary)
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .home, .weekly:
            PeriodAnalysisTab(period: .week, children: activeChildren, devices: devices, sessions: sessions)
        case .monthly:
            PeriodAnalysisTab(period: .month, children: activeChildren, devices: devices, sessions: sessions)
        case .devices:
            DevicesTab(children: activeChildren, devices: devices, sessions: sessions)
        case .children:
            ChildrenTab(children: activeChildren, devices: devices, sessions: sessions)
        }
    }
}

// MARK: - Daily insights

/// Reviewed screen-time news and statistics, shown as a card at the bottom of each
/// analysis tab.
struct DailyInsightsCard: View {
    private enum LoadState {
        case loading
        case ready([DailyInsight])
        case unavailable
    }

    @State private var state: LoadState = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Daily insights")

            switch state {
            case .loading:
                ProgressView("Loading insights…")
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("daily-insights-loading")
            case .ready(let items):
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No verified stories yet", systemImage: "newspaper")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text("Screen-time statistics, news, and expert guidance will appear here once a reviewed content source is connected.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("daily-insights-empty")
                } else {
                    ForEach(items) { insight in
                        insightRow(insight)
                        if insight.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            case .unavailable:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Insights unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text("The content could not be loaded. Your usage records are unaffected.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                    Button("Try again") { load() }
                        .font(.footnote.bold())
                }
                .accessibilityIdentifier("daily-insights-unavailable")
            }

            Text("News and statistics describe their stated region and publication date; they are not measurements of your children.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .brightCard()
        .task { load() }
    }

    private func load() {
        do {
            state = .ready(try DailyInsightsCatalog.load())
        } catch {
            state = .unavailable
        }
    }

    private func insightRow(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.kind.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
            Text(insight.title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            Text(insight.summary)
                .font(.subheadline)
            Text("\(insight.sourceName) · \(insight.region)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text("Published \(insight.publishedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            if insight.needsReview(at: .now) {
                Label("Older content — check the source for updates", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warningText)
            }
            Link(destination: insight.sourceURL) {
                Label("Read source", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityHint("Opens the original article in your browser")
        }
    }
}
