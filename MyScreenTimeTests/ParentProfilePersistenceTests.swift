import Foundation
import SwiftData
import Testing
@testable import MyScreenTime

@MainActor
struct ParentProfilePersistenceTests {
    @Test("A parent profile can be stored and fetched")
    func storesAndFetchesProfile() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ParentProfile.self,
            ChildProfile.self,
            Device.self,
            UsageSession.self,
            configurations: configuration
        )
        let context = container.mainContext

        context.insert(ParentProfile(name: "  Alex Parent  "))
        try context.save()

        let savedProfiles = try context.fetch(FetchDescriptor<ParentProfile>())

        #expect(savedProfiles.count == 1)
        #expect(savedProfiles.first?.name == "Alex Parent")
        #expect(savedProfiles.first?.notificationsEnabled == true)
    }

    @Test("Parent names are validated after trimming whitespace")
    func validatesNames() {
        #expect(ParentProfile.isValidName(" A ") == false)
        #expect(ParentProfile.isValidName(" Alex ") == true)
        #expect(ParentProfile.isValidName(String(repeating: "A", count: 51)) == false)
    }

    @Test("A child is linked to its parent and persists")
    func storesChildForParent() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ParentProfile.self,
            ChildProfile.self,
            Device.self,
            UsageSession.self,
            configurations: configuration
        )
        let context = container.mainContext
        let parent = ParentProfile(name: "Alex")
        let child = ChildProfile(name: "Sam", dailyLimitMinutes: 90, parent: parent)

        context.insert(parent)
        context.insert(child)
        try context.save()

        let children = try context.fetch(FetchDescriptor<ChildProfile>())

        #expect(children.count == 1)
        #expect(children.first?.parent?.id == parent.id)
        #expect(children.first?.dailyLimitMinutes == 90)
    }

    @Test("Child names and daily limits are validated")
    func validatesChildFields() {
        #expect(ChildProfile.isValidName(" S ") == false)
        #expect(ChildProfile.isValidName(" Sam ") == true)
        #expect(ChildProfile.isValidDailyLimit(15))
        #expect(ChildProfile.isValidDailyLimit(90))
        #expect(ChildProfile.isValidDailyLimit(10) == false)
        #expect(ChildProfile.isValidDailyLimit(1_441) == false)
    }

    @Test("A device is linked to its child and persists")
    func storesDeviceForChild() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ParentProfile.self,
            ChildProfile.self,
            Device.self,
            UsageSession.self,
            configurations: configuration
        )
        let context = container.mainContext
        let parent = ParentProfile(name: "Alex")
        let child = ChildProfile(name: "Sam", parent: parent)
        let device = Device(name: "  Sam's iPhone  ", kind: .phone, child: child)

        context.insert(parent)
        context.insert(child)
        context.insert(device)
        try context.save()

        let devices = try context.fetch(FetchDescriptor<Device>())

        #expect(devices.count == 1)
        #expect(devices.first?.name == "Sam's iPhone")
        #expect(devices.first?.kind == .phone)
        #expect(devices.first?.child?.id == child.id)
    }

    @Test("Device names are validated after trimming whitespace")
    func validatesDeviceNames() {
        #expect(Device.isValidName(" P ") == false)
        #expect(Device.isValidName(" Phone "))
        #expect(Device.isValidName(String(repeating: "D", count: 51)) == false)
    }

    @Test("A usage session can be stored, edited, and deleted")
    func managesUsageSessionPersistence() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ParentProfile.self,
            ChildProfile.self,
            Device.self,
            UsageSession.self,
            configurations: configuration
        )
        let context = container.mainContext
        let parent = ParentProfile(name: "Alex")
        let child = ChildProfile(name: "Sam", parent: parent)
        let device = Device(name: "Sam's iPhone", kind: .phone, child: child)
        let start = Date(timeIntervalSince1970: 1_000)
        let session = UsageSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(30 * 60),
            child: child,
            device: device
        )

        context.insert(parent)
        context.insert(child)
        context.insert(device)
        context.insert(session)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<UsageSession>())

        #expect(sessions.count == 1)
        #expect(sessions.first?.child?.id == child.id)
        #expect(sessions.first?.device?.id == device.id)
        #expect(sessions.first?.durationMinutes == 30)
        #expect(sessions.first?.formattedDuration == "30 min")

        session.endedAt = start.addingTimeInterval(45 * 60)
        session.note = "Homework"
        try context.save()

        let updatedSessions = try context.fetch(FetchDescriptor<UsageSession>())
        #expect(updatedSessions.first?.durationMinutes == 45)
        #expect(updatedSessions.first?.note == "Homework")

        context.delete(session)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<UsageSession>()).isEmpty)
    }

    @Test("Overlap detection applies across a child's devices")
    func detectsChildWideOverlaps() {
        let child = ChildProfile(name: "Sam")
        let sibling = ChildProfile(name: "Avery")
        let start = Date(timeIntervalSince1970: 10_000)
        let existing = UsageSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(60 * 60),
            child: child
        )
        let siblingSession = UsageSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(60 * 60),
            child: sibling
        )

        #expect(UsageSession.hasOverlap(
            startedAt: start.addingTimeInterval(30 * 60),
            endedAt: start.addingTimeInterval(90 * 60),
            childID: child.id,
            among: [existing, siblingSession]
        ))
        #expect(UsageSession.hasOverlap(
            startedAt: start.addingTimeInterval(60 * 60),
            endedAt: start.addingTimeInterval(90 * 60),
            childID: child.id,
            among: [existing]
        ) == false)
        #expect(UsageSession.hasOverlap(
            startedAt: start,
            endedAt: start.addingTimeInterval(30 * 60),
            childID: child.id,
            excluding: existing.id,
            among: [existing]
        ) == false)
    }

    @Test("Daily totals combine a child's devices and keep device subtotals")
    func calculatesDailyTotals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let child = ChildProfile(name: "Sam", dailyLimitMinutes: 120)
        let sibling = ChildProfile(name: "Avery", dailyLimitMinutes: 120)
        let phone = Device(name: "Phone", kind: .phone, child: child)
        let tv = Device(name: "TV", kind: .television, child: child)
        let sessions = [
            UsageSession(
                startedAt: day.addingTimeInterval(9 * 60 * 60),
                endedAt: day.addingTimeInterval(9 * 60 * 60 + 30 * 60),
                child: child,
                device: phone
            ),
            UsageSession(
                startedAt: day.addingTimeInterval(12 * 60 * 60),
                endedAt: day.addingTimeInterval(12 * 60 * 60 + 45 * 60),
                child: child,
                device: tv
            ),
            UsageSession(
                startedAt: day.addingTimeInterval(15 * 60 * 60),
                endedAt: day.addingTimeInterval(16 * 60 * 60),
                child: sibling,
                device: nil
            ),
            UsageSession(
                startedAt: day.addingTimeInterval(24 * 60 * 60 + 60),
                endedAt: day.addingTimeInterval(24 * 60 * 60 + 20 * 60),
                child: child,
                device: phone
            )
        ]

        let summary = UsageAggregator.summary(
            on: day,
            child: child,
            sessions: sessions,
            calendar: calendar
        )

        #expect(summary.usedMinutes == 75)
        #expect(summary.remainingMinutes == 45)
        #expect(summary.overMinutes == 0)
        #expect(summary.status == .normal)
        #expect(UsageAggregator.totalMinutes(
            on: day,
            deviceID: phone.id,
            sessions: sessions,
            calendar: calendar
        ) == 30)
    }

    @Test("Daily-limit summaries report near, reached, and exceeded states")
    func calculatesDailyLimitStates() {
        let near = DailyUsageSummary(usedMinutes: 96, limitMinutes: 120)
        let reached = DailyUsageSummary(usedMinutes: 120, limitMinutes: 120)
        let exceeded = DailyUsageSummary(usedMinutes: 150, limitMinutes: 120)

        #expect(near.status == .nearLimit)
        #expect(near.remainingMinutes == 24)
        #expect(reached.status == .reached)
        #expect(reached.remainingMinutes == 0)
        #expect(exceeded.status == .exceeded)
        #expect(exceeded.remainingMinutes == 0)
        #expect(exceeded.overMinutes == 30)
        #expect(exceeded.progress == 1)
        #expect(exceeded.statusText == "2 hr 30 min used • 30 min over")
    }

    @Test("Daily totals use exact local midnight boundaries")
    func calculatesTotalsAtMidnightBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let child = ChildProfile(name: "Sam")
        let sessions = [
            UsageSession(
                startedAt: day.addingTimeInterval(-60),
                endedAt: day,
                child: child
            ),
            UsageSession(
                startedAt: day,
                endedAt: day.addingTimeInterval(15 * 60),
                child: child
            ),
            UsageSession(
                startedAt: nextDay.addingTimeInterval(-15 * 60),
                endedAt: nextDay,
                child: child
            ),
            UsageSession(
                startedAt: nextDay,
                endedAt: nextDay.addingTimeInterval(20 * 60),
                child: child
            )
        ]

        #expect(UsageAggregator.totalMinutes(
            on: day,
            childID: child.id,
            sessions: sessions,
            calendar: calendar
        ) == 30)
        #expect(UsageAggregator.totalMinutes(
            on: nextDay,
            childID: child.id,
            sessions: sessions,
            calendar: calendar
        ) == 20)
    }

    @Test("Daily totals follow the selected time zone")
    func calculatesTotalsInSelectedTimeZone() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let utcDay = utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let localDay = newYorkCalendar.date(from: DateComponents(year: 2026, month: 9, day: 11))!
        let localNextDay = newYorkCalendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let child = ChildProfile(name: "Sam")
        let session = UsageSession(
            startedAt: utcDay.addingTimeInterval(30 * 60),
            endedAt: utcDay.addingTimeInterval(60 * 60),
            child: child
        )

        #expect(UsageAggregator.totalMinutes(
            on: utcDay,
            childID: child.id,
            sessions: [session],
            calendar: utcCalendar
        ) == 30)
        #expect(UsageAggregator.totalMinutes(
            on: localDay,
            childID: child.id,
            sessions: [session],
            calendar: newYorkCalendar
        ) == 30)
        #expect(UsageAggregator.totalMinutes(
            on: localNextDay,
            childID: child.id,
            sessions: [session],
            calendar: newYorkCalendar
        ) == 0)
    }

    @Test("A child can use separate weekday and weekend limits")
    func selectsWeekdayAndWeekendLimits() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19))!
        let child = ChildProfile(
            name: "Sam",
            dailyLimitMinutes: 120,
            weekdayLimitMinutes: 90,
            weekendLimitMinutes: 180
        )

        #expect(child.limitMinutes(on: monday, calendar: calendar) == 90)
        #expect(child.limitMinutes(on: saturday, calendar: calendar) == 180)
        #expect(UsageAggregator.summary(
            on: monday,
            child: child,
            sessions: [],
            calendar: calendar
        ).remainingMinutes == 90)
        #expect(UsageAggregator.summary(
            on: saturday,
            child: child,
            sessions: [],
            calendar: calendar
        ).remainingMinutes == 180)
    }

    @Test("The standard daily limit remains the fallback")
    func usesStandardDailyLimitWithoutSchedule() {
        let child = ChildProfile(name: "Sam", dailyLimitMinutes: 105)

        #expect(child.limitMinutes(on: .now) == 105)
    }
}
