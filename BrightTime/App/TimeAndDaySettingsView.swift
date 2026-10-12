import SwiftUI

/// Settings → Time & Day: which time zone the family runs on, when a new day
/// starts, and which day starts the week. Changes apply immediately.
struct TimeAndDaySettingsView: View {
    @AppStorage(AppCalendar.Keys.automaticTimeZone) private var isAutomatic = true
    @AppStorage(AppCalendar.Keys.manualTimeZone) private var manualZoneID = ""
    @AppStorage(AppCalendar.Keys.dayResetHour) private var resetHour = 0
    @AppStorage(AppCalendar.Keys.firstWeekday) private var firstWeekday = 0

    private var activeZone: TimeZone {
        if !isAutomatic, let zone = TimeZone(identifier: manualZoneID) { return zone }
        return AppCalendar.deviceTimeZone
    }

    var body: some View {
        Form {
            Section {
                Toggle("Set automatically", isOn: $isAutomatic)
                    .accessibilityIdentifier("time-zone-automatic-toggle")

                if isAutomatic {
                    zoneSummary(activeZone)
                } else {
                    NavigationLink {
                        TimeZonePickerView(selection: $manualZoneID)
                    } label: {
                        zoneSummary(activeZone)
                    }
                    .accessibilityIdentifier("time-zone-picker-link")
                }
            } header: {
                Text("Time zone")
            } footer: {
                Text(isAutomatic
                     ? "Follows this iPhone. If you travel, \u{201C}today\u{201D} stays in sync with where you are, including daylight saving."
                     : "BrightTime counts days in this zone even if the iPhone moves. Useful if your kids live in a different time zone.")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                Picker("Day resets at", selection: $resetHour) {
                    ForEach(AppCalendar.resetHourChoices, id: \.self) { hour in
                        Text(AppCalendar.resetHourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("day-reset-picker")
            } header: {
                Text("Day resets at")
            } footer: {
                Text(resetHour == 0
                     ? "Each day runs midnight to midnight."
                     : "Late-night use, like 12:30 AM, counts toward the evening it started in, not the next day's limit.")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                Picker("Week starts on", selection: $firstWeekday) {
                    Text("Region").tag(0)
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text("Week starts on")
            } footer: {
                Text("Used by the Weekly and Monthly tabs.")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Time & Day")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isAutomatic) { _, automatic in
            if !automatic, TimeZone(identifier: manualZoneID) == nil {
                manualZoneID = AppCalendar.deviceTimeZone.identifier
            }
            AppCalendar.apply()
        }
        .onChange(of: manualZoneID) { _, _ in AppCalendar.apply() }
        .onChange(of: resetHour) { _, _ in AppCalendar.apply() }
        .onChange(of: firstWeekday) { _, _ in AppCalendar.apply() }
    }

    private func zoneSummary(_ zone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppCalendar.name(of: zone))
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primaryDeep)
            Text(AppCalendar.shortDescription(of: zone))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Searchable list of every time zone, shown as "Eastern Time · Toronto · GMT−4".
struct TimeZonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private struct ZoneRow: Identifiable {
        let id: String
        let name: String
        let city: String
        let offset: String
        let secondsFromGMT: Int
    }

    private static let allZones: [ZoneRow] = TimeZone.knownTimeZoneIdentifiers
        .compactMap { TimeZone(identifier: $0) }
        .filter { $0.identifier.contains("/") && !$0.identifier.hasPrefix("Etc/") }
        .map { zone in
            ZoneRow(
                id: zone.identifier,
                name: AppCalendar.name(of: zone),
                city: AppCalendar.city(of: zone),
                offset: AppCalendar.offset(of: zone),
                secondsFromGMT: zone.secondsFromGMT()
            )
        }
        .sorted { ($0.secondsFromGMT, $0.city) < ($1.secondsFromGMT, $1.city) }

    private var rows: [ZoneRow] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Self.allZones }
        return Self.allZones.filter {
            $0.city.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(rows) { row in
            Button {
                selection = row.id
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.city)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text("\(row.name) · \(row.offset)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    if row.id == selection {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(AppTheme.primary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .searchable(text: $search, prompt: "City or time zone")
        .navigationTitle("Time Zone")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Home-screen notice when the iPhone's time zone changes. In automatic mode it's
/// a heads-up ("now on Pacific Time"); with a fixed zone it asks whether to switch.
/// It never changes anything without the parent seeing it.
struct TimeZoneNotice: View {
    @AppStorage(AppCalendar.Keys.automaticTimeZone) private var isAutomatic = true
    @AppStorage(AppCalendar.Keys.manualTimeZone) private var manualZoneID = ""
    @AppStorage(AppCalendar.Keys.lastSeenTimeZone) private var lastSeenZoneID = ""
    @AppStorage(AppCalendar.Keys.dismissedTimeZone) private var dismissedZoneID = ""
    @AppStorage(AppCalendar.Keys.revision) private var calendarRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = calendarRevision
        let device = AppCalendar.deviceTimeZone

        Group {
            if isAutomatic {
                if !lastSeenZoneID.isEmpty, lastSeenZoneID != device.identifier,
                   let previous = TimeZone(identifier: lastSeenZoneID) {
                    card(
                        title: "Now on \(AppCalendar.name(of: device))",
                        message: "Your iPhone moved to \(AppCalendar.city(of: device)). Today's limits and timers now follow it (was \(AppCalendar.name(of: previous))).",
                        primary: ("Got it", { remember(device) }),
                        secondary: ("Keep \(AppCalendar.city(of: previous))", {
                            manualZoneID = previous.identifier
                            isAutomatic = false
                            dismissedZoneID = device.identifier
                            remember(device)
                        })
                    )
                }
            } else if let manual = TimeZone(identifier: manualZoneID),
                      manual.secondsFromGMT() != device.secondsFromGMT(),
                      dismissedZoneID != device.identifier {
                card(
                    title: "You're in a new time zone",
                    message: "Your iPhone is on \(AppCalendar.name(of: device)) (\(AppCalendar.city(of: device))). Use it for today's limits and timers?",
                    primary: ("Use \(AppCalendar.city(of: device))", {
                        isAutomatic = true
                        dismissedZoneID = ""
                        remember(device)
                    }),
                    secondary: ("Keep \(AppCalendar.city(of: manual))", {
                        dismissedZoneID = device.identifier
                    })
                )
            }
        }
        .animation(AppTheme.motion(reduceMotion: reduceMotion), value: lastSeenZoneID)
        .animation(AppTheme.motion(reduceMotion: reduceMotion), value: dismissedZoneID)
        .onAppear {
            if lastSeenZoneID.isEmpty { lastSeenZoneID = device.identifier }
        }
    }

    private func remember(_ zone: TimeZone) {
        lastSeenZoneID = zone.identifier
        AppCalendar.apply()
    }

    private func card(
        title: String,
        message: String,
        primary: (String, () -> Void),
        secondary: (String, () -> Void)
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "globe")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryDeep)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: primary.1) {
                    Text(primary.0)
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppTheme.primary, in: Capsule())
                }
                Button(action: secondary.1) {
                    Text(secondary.0)
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.primaryDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppTheme.surfaceMuted, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .brightCard(padding: 14)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.primary.opacity(0.4), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
