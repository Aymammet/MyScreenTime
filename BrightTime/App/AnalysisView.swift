import SwiftData
import SwiftUI

enum AnalysisDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case insights = "Insights"
    case children = "Kids"
    case devices = "Devices"
    case profile = "Profile"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .insights: "chart.bar.fill"
        case .children: "person.2.fill"
        case .devices: "ipad.and.iphone"
        case .profile: "person.crop.circle.fill"
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
        case .home, .insights, .profile:
            InsightsTab(children: activeChildren, devices: devices, sessions: sessions)
        case .devices:
            DevicesTab(children: activeChildren, devices: devices, sessions: sessions)
        case .children:
            ChildrenTab(children: activeChildren, devices: devices, sessions: sessions)
        }
    }
}

/// Week and month in one tab. The Week / Month switch stays pinned above the
/// scrolling content, like the Screen Time screen in iPhone Settings.
struct InsightsTab: View {
    let children: [ChildProfile]
    let devices: [Device]
    let sessions: [UsageSession]

    @AppStorage("brighttime.insights.period") private var period: AnalysisPeriod = .week

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $period) {
                ForEach(AnalysisPeriod.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("insights-period-picker")

            PeriodAnalysisTab(period: period, children: children, devices: devices, sessions: sessions)
                .id(period)
        }
        .sensoryFeedback(.selection, trigger: period)
    }
}

// MARK: - Parent Brief

/// Reviewed screen-time news, research, and guidance. Home can request one compact
/// story; analysis tabs show the full briefing.
struct DailyInsightsCard: View {
    private enum LoadState {
        case loading
        case ready([DailyInsight])
        case unavailable
    }

    @State private var state: LoadState = .loading
    var maximumItems: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "newspaper.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.primaryTint, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("Parent Brief")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryDeep)
                    Text("Research, news & practical guidance")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Label("Reviewed", systemImage: "checkmark.seal.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.primaryTint, in: Capsule())
            }

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
                    ForEach(Array(items.prefix(maximumItems ?? items.count))) { insight in
                        insightRow(insight)
                        if insight.id != Array(items.prefix(maximumItems ?? items.count)).last?.id {
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

            Text(maximumItems == nil
                 ? "Briefs show their source, region, and publication date. They are not measurements of your kids."
                 : "Find more research and news in Insights.")
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
            Label(insight.kind.title, systemImage: insight.kind.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(insight.kind.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(insight.kind.color.opacity(0.12), in: Capsule())
            Text(insight.title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            Text(insight.summary)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Label(insight.region, systemImage: "globe.americas.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            if insight.needsReview(at: .now) {
                Label("Older content — check the source for updates", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warningText)
            }
            Link(destination: insight.sourceURL) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.sourceName)
                            .font(.caption.weight(.bold))
                        Text(insight.publishedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                }
                .padding(10)
                .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityHint("Opens the original article in your browser")
        }
    }
}

private extension DailyInsight.Kind {
    var title: String {
        switch self {
        case .statistic: "Research"
        case .news: "Policy news"
        case .guidance: "Parent guide"
        }
    }

    var systemImage: String {
        switch self {
        case .statistic: "chart.bar.fill"
        case .news: "building.columns.fill"
        case .guidance: "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .statistic: Color(hex: 0x7B61D1)
        case .news: Color(hex: 0x3B7DD8)
        case .guidance: AppTheme.warningText
        }
    }
}
