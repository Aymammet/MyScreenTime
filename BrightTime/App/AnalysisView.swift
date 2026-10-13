import SwiftData
import SwiftUI

enum AnalysisDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case insights = "Insights"
    case children = "Kids"
    case devices = "Devices"
    case profile = "Settings"

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
    @State private var isShowingRecap = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingRecap = true
                } label: {
                    Label("Weekly recap", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("insights-recap-button")
            }
        }
        .sheet(isPresented: $isShowingRecap) {
            WeeklyRecapView()
        }
    }
}

// MARK: - Parent Brief

/// Reviewed screen-time news, research, and guidance, shown on Home one story at
/// a time. Stories rotate every 15 seconds; swipe or tap a dot to move yourself.
struct DailyInsightsCard: View {
    private enum LoadState {
        case loading
        case ready([DailyInsight])
        case unavailable
    }

    /// How long each story stays before the next one slides in.
    static let rotationInterval: Duration = .seconds(15)

    @State private var state: LoadState = .loading
    @State private var currentIndex = 0
    /// +1 when moving forward, -1 when going back, so the slide runs the right way.
    @State private var direction = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

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
                    carousel(items)
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

            Text("Briefs show their source, region, and publication date. They are not measurements of your kids.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .brightCard()
        .task { load() }
    }

    private func load() {
        do {
            let items = try DailyInsightsCatalog.load()
            state = .ready(items)
            // Start on a different story each day, so Home doesn't always open
            // on the same one.
            if !items.isEmpty {
                let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
                currentIndex = day % items.count
            }
        } catch {
            state = .unavailable
        }
    }

    // MARK: - Carousel

    @ViewBuilder
    private func carousel(_ items: [DailyInsight]) -> some View {
        let index = min(currentIndex, items.count - 1)
        let insight = items[index]

        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                insightRow(insight)
                    .id(insight.id)
                    .transition(slideTransition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        step(value.translation.width < 0 ? 1 : -1, count: items.count)
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityAdjustableAction { adjustment in
                switch adjustment {
                case .increment: step(1, count: items.count)
                case .decrement: step(-1, count: items.count)
                @unknown default: break
                }
            }

            if items.count > 1 {
                pageDots(count: items.count, current: index)
            }
        }
        // Restarts the 15-second wait whenever the story changes, so a swipe
        // gives the reader a full 15 seconds on the new one.
        .task(id: index) {
            guard items.count > 1, !voiceOverEnabled else { return }
            try? await Task.sleep(for: Self.rotationInterval)
            guard !Task.isCancelled else { return }
            step(1, count: items.count)
        }
    }

    private var slideTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func step(_ delta: Int, count: Int) {
        guard count > 1 else { return }
        direction = delta >= 0 ? 1 : -1
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.9)) {
            currentIndex = (min(currentIndex, count - 1) + delta + count) % count
        }
    }

    private func pageDots(count: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Button {
                    guard dot != current else { return }
                    step(dot - current, count: count)
                } label: {
                    Capsule()
                        .fill(dot == current ? AppTheme.primary : AppTheme.textTertiary.opacity(0.45))
                        .frame(width: dot == current ? 18 : 6, height: 6)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Story \(dot + 1) of \(count)")
                .accessibilityAddTraits(dot == current ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .animation(AppTheme.spring, value: current)
        .accessibilityIdentifier("daily-insights-dots")
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
