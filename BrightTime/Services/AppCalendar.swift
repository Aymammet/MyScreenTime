import Foundation

/// One source of truth for "what day is it" across BrightTime: which time zone the
/// family runs on, when the day rolls over, and which day starts the week.
///
/// - Time zone: automatic (follows the iPhone) or a fixed zone the parent picks.
///   Applied app-wide through `NSTimeZone.default`, so every `Calendar.current`,
///   date formatter and chart agrees.
/// - Day reset: usage at 12:30 AM can count toward the evening it started in.
/// - Week start: Sunday, Monday, or the region's default.
enum AppCalendar {
    enum Keys {
        static let automaticTimeZone = "brighttime.time.automatic"
        static let manualTimeZone = "brighttime.time.zoneID"
        static let dayResetHour = "brighttime.day.resetHour"
        static let firstWeekday = "brighttime.week.firstWeekday"
        /// Bumped whenever any calendar setting changes, so open screens redraw.
        static let revision = "brighttime.calendar.revision"
        /// The zone the app last ran in (automatic mode), for the "new time zone" notice.
        static let lastSeenTimeZone = "brighttime.time.lastSeen"
        /// A device zone the parent chose to ignore (manual mode).
        static let dismissedTimeZone = "brighttime.time.dismissed"
    }

    /// Hours the parent can pick for when a new day starts.
    static let resetHourChoices = [0, 3, 4, 5]

    private static var defaults: UserDefaults { .standard }

    static var isAutomatic: Bool {
        defaults.object(forKey: Keys.automaticTimeZone) as? Bool ?? true
    }

    static var manualTimeZoneID: String? {
        defaults.string(forKey: Keys.manualTimeZone)
    }

    static var dayResetHour: Int {
        let hour = defaults.integer(forKey: Keys.dayResetHour)
        return resetHourChoices.contains(hour) ? hour : 0
    }

    /// 0 = region default, 1 = Sunday, 2 = Monday.
    static var firstWeekday: Int {
        defaults.integer(forKey: Keys.firstWeekday)
    }

    /// The zone the iPhone itself is set to, ignoring any manual override.
    static var deviceTimeZone: TimeZone {
        NSTimeZone.resetSystemTimeZone()
        return NSTimeZone.system
    }

    /// The zone BrightTime counts days in.
    static var effectiveTimeZone: TimeZone {
        if !isAutomatic, let id = manualTimeZoneID, let zone = TimeZone(identifier: id) {
            return zone
        }
        return deviceTimeZone
    }

    /// Calendar for showing times and dates to people (clock hours, labels).
    static var display: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = effectiveTimeZone
        if firstWeekday != 0 { calendar.firstWeekday = firstWeekday }
        return calendar
    }

    /// Calendar for counting usage into days, weeks and months. Same as `display`,
    /// except that when the day resets after midnight its days run from the reset
    /// hour to the reset hour (e.g. 3 AM to 3 AM).
    ///
    /// The shift uses the zone's current UTC offset, so across a daylight-saving
    /// change the boundary on the far side can land an hour early or late. That
    /// only affects sessions within an hour of the reset time on those dates.
    static var day: Calendar {
        var calendar = display
        let resetHour = dayResetHour
        if resetHour > 0 {
            let offset = calendar.timeZone.secondsFromGMT(for: .now) - resetHour * 3_600
            calendar.timeZone = TimeZone(secondsFromGMT: offset) ?? calendar.timeZone
        }
        return calendar
    }

    /// Makes the whole app use the chosen zone, then tells open screens to refresh.
    /// Call at launch, when the app becomes active, and after any setting changes.
    static func apply() {
        NSTimeZone.default = effectiveTimeZone
        defaults.set(defaults.integer(forKey: Keys.revision) &+ 1, forKey: Keys.revision)
    }

    // MARK: - Friendly names

    /// "Eastern Time"
    static func name(of zone: TimeZone) -> String {
        zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
    }

    /// "Toronto"
    static func city(of zone: TimeZone) -> String {
        let last = zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// "GMT−4"
    static func offset(of zone: TimeZone, at date: Date = .now) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let hours = seconds / 3_600
        let minutes = abs(seconds % 3_600) / 60
        let sign = seconds < 0 ? "−" : "+"
        if seconds == 0 { return "GMT" }
        return minutes == 0 ? "GMT\(sign)\(abs(hours))" : "GMT\(sign)\(abs(hours)):\(String(format: "%02d", minutes))"
    }

    /// "Toronto · GMT−4"
    static func shortDescription(of zone: TimeZone) -> String {
        "\(city(of: zone)) · \(offset(of: zone))"
    }

    static func resetHourLabel(_ hour: Int) -> String {
        guard hour > 0,
              let date = display.date(bySettingHour: hour, minute: 0, second: 0, of: .now) else {
            return "Midnight"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
