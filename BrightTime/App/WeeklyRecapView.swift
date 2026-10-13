import SwiftData
import SwiftUI

/// The Monday report: the family's last completed week, each kid's streak and best day, and a
/// card to share in the family chat.
struct WeeklyRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ChildProfile.createdAt) private var children: [ChildProfile]
    @Query private var sessions: [UsageSession]
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0

    @State private var shareImage: Image?

    private var recap: WeeklyRecap {
        _ = calendarRevision
        return WeeklyRecapCalculator.make(children: children, sessions: sessions)
    }

    var body: some View {
        let recap = recap
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RecapHero(recap: recap)
                    if recap.kids.isEmpty {
                        Text("Add a kid to see a weekly recap.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .brightCard()
                    }
                    ForEach(recap.kids) { kid in
                        RecapKidCard(kid: kid)
                    }
                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            preview: SharePreview("Our week in BrightTime", image: shareImage)
                        ) {
                            Label("Share this week", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundStyle(AppTheme.onPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.primary, in: Capsule())
                        }
                        .accessibilityIdentifier("recap-share")
                        Text("Shares a picture of this summary. Nothing is uploaded.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task(id: recap) {
                renderShareCard(recap)
            }
        }
    }

    private func renderShareCard(_ recap: WeeklyRecap) {
        guard !recap.kids.isEmpty else {
            shareImage = nil
            return
        }
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap))
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareImage = Image(uiImage: image)
        }
    }
}

/// Past completed weeks remain available from Profile. Reports are calculated
/// from the usage records BrightTime already keeps, so there is no duplicate copy
/// that can drift out of sync after a parent corrects an entry.
struct WeeklyReportHistoryView: View {
    @Query(sort: \ChildProfile.createdAt) private var children: [ChildProfile]
    @Query(sort: \UsageSession.startedAt, order: .reverse) private var sessions: [UsageSession]
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0

    private var reportIntervals: [DateInterval] {
        _ = calendarRevision
        let latest = WeeklyRecapCalculator.recapInterval()
        var intervals: [DateInterval] = []
        var end = latest.end
        let calendar = AppCalendar.day

        for _ in 0..<52 {
            guard let start = calendar.date(byAdding: .day, value: -7, to: end) else { break }
            let interval = DateInterval(start: start, end: end)
            if sessions.contains(where: { $0.startedAt < interval.end && $0.endedAt > interval.start }) {
                intervals.append(interval)
            }
            end = start
        }
        return intervals
    }

    var body: some View {
        Group {
            if reportIntervals.isEmpty {
                ContentUnavailableView(
                    "No weekly reports yet",
                    systemImage: "calendar.badge.clock",
                    description: Text("A completed week with recorded usage will appear here after Sunday ends.")
                )
            } else {
                List(reportIntervals, id: \.start) { interval in
                    let recap = WeeklyRecapCalculator.make(
                        children: children,
                        sessions: sessions,
                        interval: interval
                    )
                    NavigationLink {
                        WeeklyReportHistoryDetail(recap: recap)
                    } label: {
                        WeeklyReportHistoryRow(recap: recap)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
            }
        }
        .navigationTitle("Weekly Reports")
        .navigationBarTitleDisplayMode(.large)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

private struct WeeklyReportHistoryRow: View {
    let recap: WeeklyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recap.title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryDeep)
            HStack(spacing: 8) {
                Text(TimeText.compact(recap.totalMinutes))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if recap.previousMinutes > 0 {
                    Label(
                        TimeText.compact(abs(recap.change)),
                        systemImage: recap.change <= 0 ? "arrow.down.right" : "arrow.up.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recap.change <= 0 ? AppTheme.primary : AppTheme.warningText)
                }
                Spacer()
                Text("\(recap.kids.count) kid\(recap.kids.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WeeklyReportHistoryDetail: View {
    let recap: WeeklyRecap
    @State private var shareImage: Image?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RecapHero(recap: recap)
                ForEach(recap.kids) { kid in
                    RecapKidCard(kid: kid)
                }
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview("Our week in BrightTime", image: shareImage)
                    ) {
                        Label("Share this report", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(AppTheme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.primary, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(recap.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: recap) {
            let renderer = ImageRenderer(content: RecapShareCard(recap: recap))
            renderer.scale = 3
            shareImage = renderer.uiImage.map { Image(uiImage: $0) }
        }
    }
}

// MARK: - Pieces

private struct RecapHero: View {
    let recap: WeeklyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recap.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.heroText.opacity(0.8))
            Text("Family screen time")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.heroText.opacity(0.9))
            Text(TimeText.compact(recap.totalMinutes))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.heroText)
            HStack(spacing: 8) {
                chip(changeText, systemImage: recap.change <= 0 ? "arrow.down.right" : "arrow.up.right")
                if let best = recap.bestDay {
                    chip("Best day: \(best.formatted(.dateTime.weekday(.wide)))", systemImage: "sun.max.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.heroBorder, lineWidth: 1)
        }
    }

    private var changeText: String {
        guard recap.previousMinutes > 0 else { return "First week tracked" }
        if recap.change == 0 { return "Same as last week" }
        let amount = TimeText.compact(abs(recap.change))
        return recap.change < 0 ? "\(amount) less than last week" : "\(amount) more than last week"
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.heroText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.heroChip, in: Capsule())
            .lineLimit(1)
    }
}

private struct RecapKidCard: View {
    let kid: WeeklyRecap.Kid

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color(hex: kid.colorHex))
                    .frame(width: 12, height: 12)
                Text(kid.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryDeep)
                Spacer()
                Text(TimeText.compact(kid.totalMinutes))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.primaryDeep)
            }
            HStack(spacing: 8) {
                stat("\(kid.daysOnTrack)/\(kid.daysCounted)", label: "days on track", icon: "checkmark.circle.fill", tint: AppTheme.primary)
                stat(kid.streak > 0 ? "\(kid.streak) day\(kid.streak == 1 ? "" : "s")" : "–", label: "streak", icon: "flame.fill", tint: AppTheme.warning)
                stat(kid.earnedMinutes > 0 ? "+\(TimeText.compact(kid.earnedMinutes))" : "–", label: "earned", icon: "star.fill", tint: AppTheme.warning)
            }
            if let best = kid.bestDay {
                Label("Best day: \(best.formatted(.dateTime.weekday(.wide)))", systemImage: "sun.max.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .brightCard()
    }

    private func stat(_ value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryDeep)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The picture that gets shared: fixed size and colors, so it looks the same in
/// any chat whatever the phone's light or dark setting.
struct RecapShareCard: View {
    let recap: WeeklyRecap

    private let ink = Color(hex: 0xF2F2EF)
    private let quiet = Color(hex: 0x9FD3CE)
    private let teal = Color(hex: 0x3FB0A9)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(teal)
                Text("BrightTime")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Text(recap.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(quiet)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Our week")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(quiet)
                Text(TimeText.compact(recap.totalMinutes))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                if recap.previousMinutes > 0 && recap.change != 0 {
                    Text(recap.change < 0
                         ? "\(TimeText.compact(-recap.change)) less screen time than last week"
                         : "\(TimeText.compact(recap.change)) more than last week")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(recap.change < 0 ? teal : Color(hex: 0xF0AE45))
                }
            }
            VStack(spacing: 10) {
                ForEach(recap.kids) { kid in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: kid.colorHex))
                            .frame(width: 10, height: 10)
                        Text(kid.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ink)
                        Spacer()
                        if kid.streak > 1 {
                            Label("\(kid.streak)-day streak", systemImage: "flame.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(hex: 0xF0AE45))
                        }
                        if kid.earnedMinutes > 0 {
                            Label("+\(TimeText.compact(kid.earnedMinutes))", systemImage: "star.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(hex: 0xF0AE45))
                        }
                        Text("\(kid.daysOnTrack)/\(kid.daysCounted) on track")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(quiet)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            if let best = recap.bestDay {
                Text("Best day: \(best.formatted(.dateTime.weekday(.wide)))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(quiet)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Color(hex: 0x0F2E2C), Color(hex: 0x050A0A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
    }
}
