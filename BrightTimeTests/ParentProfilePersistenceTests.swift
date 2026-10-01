import Foundation
import SwiftData
import Testing
@testable import BrightTime

@MainActor
struct ParentProfilePersistenceTests {
    @Test("Daily insights require source metadata and secure links")
    func validatesDailyInsightMetadata() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func insight(source: String = "Reviewed publisher", link: String = "https://example.org/article", date: Date? = nil) -> DailyInsight {
            DailyInsight(id: "test", kind: .news, title: "Test title", summary: "Test summary", sourceName: source,
                         publishedAt: date ?? now, reviewedAt: now, region: "Test region", sourceURL: URL(string: link)!)
        }
        #expect(insight().isValid(at: now))
        #expect(!insight(source: "  ").isValid(at: now))
        #expect(!insight(link: "http://example.org/article").isValid(at: now))
        #expect(!insight(date: now.addingTimeInterval(60)).isValid(at: now))
        #expect(!insight().needsReview(at: now))
        #expect(insight().needsReview(at: now.addingTimeInterval(31 * 24 * 60 * 60)))
    }

    @Test("Daily insights decode reviewed content and reject malformed catalogs")
    func decodesDailyInsightsCatalog() throws {
        let item = DailyInsight(id: "fixture", kind: .statistic, title: "Test statistic", summary: "Fixture only",
                                sourceName: "Test source", publishedAt: Date(timeIntervalSince1970: 1_000),
                                reviewedAt: Date(timeIntervalSince1970: 2_000), region: "Test region",
                                sourceURL: URL(string: "https://example.org/report")!)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let result = try DailyInsightsCatalog.decode(encoder.encode([item]), now: Date(timeIntervalSince1970: 3_000))
        #expect(result == [item])
        #expect(throws: (any Error).self) {
            try DailyInsightsCatalog.decode(Data("not json".utf8), now: .now)
        }
    }

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

    @Test("Default avatar catalog contains five choices for each gender")
    func validatesDefaultAvatarCatalog() {
        #expect(ChildGender.boy.avatarChoices.count == 5)
        #expect(ChildGender.girl.avatarChoices.count == 5)
        #expect(ChildGender.boy.avatarChoices.allSatisfy { $0.gender == .boy })
        #expect(ChildGender.girl.avatarChoices.allSatisfy { $0.gender == .girl })

        let child = ChildProfile(name: "Sam", gender: .girl, defaultAvatar: .girl4)
        let parent = ParentProfile(name: "Alex", defaultAvatar: .boy3)
        #expect(child.resolvedDefaultAvatar == .girl4)
        #expect(parent.resolvedDefaultAvatar == .boy3)
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

    @Test("A shared device is available to every child and persists without a child owner")
    func storesSharedDevice() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ParentProfile.self,
            ChildProfile.self,
            Device.self,
            UsageSession.self,
            configurations: configuration
        )
        let context = container.mainContext
        let sam = ChildProfile(name: "Sam")
        let avery = ChildProfile(name: "Avery")
        let tv = Device(name: "Home TV", kind: .television, isShared: true)

        context.insert(sam)
        context.insert(avery)
        context.insert(tv)
        try context.save()

        let saved = try #require(context.fetch(FetchDescriptor<Device>()).first)
        #expect(saved.isShared)
        #expect(saved.child == nil)
        #expect(saved.isAvailable(to: sam.id))
        #expect(saved.isAvailable(to: avery.id))
    }

    @Test("Shared device usage stays attributed to each child")
    func attributesSharedDeviceUsage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 10))!
        let sam = ChildProfile(name: "Sam")
        let avery = ChildProfile(name: "Avery")
        let tv = Device(name: "Home TV", kind: .television, isShared: true)
        let sessions = [
            UsageSession(startedAt: day, endedAt: day.addingTimeInterval(30 * 60), child: sam, device: tv),
            UsageSession(startedAt: day.addingTimeInterval(60 * 60), endedAt: day.addingTimeInterval(105 * 60), child: avery, device: tv)
        ]

        #expect(UsageAggregator.totalMinutes(on: day, deviceID: tv.id, sessions: sessions, calendar: calendar) == 75)
        #expect(UsageAggregator.totalMinutes(on: day, childID: sam.id, deviceID: tv.id, sessions: sessions, calendar: calendar) == 30)
        #expect(UsageAggregator.totalMinutes(on: day, childID: avery.id, deviceID: tv.id, sessions: sessions, calendar: calendar) == 45)
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

    @Test("Period totals include only the parent's children and interval")
    func calculatesAnalysisPeriodTotals() {
        let child = ChildProfile(name: "Sam")
        let sibling = ChildProfile(name: "Avery")
        let start = Date(timeIntervalSince1970: 1_000_000)
        let interval = DateInterval(start: start, duration: 7 * 24 * 60 * 60)
        let sessions = [
            UsageSession(startedAt: start, endedAt: start.addingTimeInterval(30 * 60), child: child),
            UsageSession(startedAt: start.addingTimeInterval(24 * 60 * 60), endedAt: start.addingTimeInterval(24 * 60 * 60 + 45 * 60), child: child),
            UsageSession(startedAt: start, endedAt: start.addingTimeInterval(60 * 60), child: sibling),
            UsageSession(startedAt: interval.end, endedAt: interval.end.addingTimeInterval(20 * 60), child: child)
        ]

        #expect(UsageAggregator.totalMinutes(
            in: interval,
            childIDs: [child.id],
            sessions: sessions
        ) == 75)
    }

    @Test("Screen timers preserve their requested duration")
    func calculatesScreenTimerDuration() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let timer = ActiveScreenTimer(
            id: UUID(),
            childID: UUID(),
            childName: "John",
            deviceID: UUID(),
            deviceName: "TV",
            startedAt: start,
            endsAt: start.addingTimeInterval(30 * 60)
        )

        #expect(timer.durationMinutes == 30)
    }

    @Test("A child's profile photo is stored with their profile")
    func storesChildProfilePhoto() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ParentProfile.self,
            ChildProfile.self,
            Device.self,
            UsageSession.self,
            configurations: configuration
        )
        let context = container.mainContext
        let photo = Data([0x01, 0x02, 0x03])
        let child = ChildProfile(name: "Sam", profilePhotoData: photo)
        context.insert(child)
        try context.save()

        let saved = try context.fetch(FetchDescriptor<ChildProfile>()).first
        #expect(saved?.profilePhotoData == photo)
    }

    @Test("Analysis compares matching portions of incomplete weeks")
    func comparesIncompleteAnalysisPeriods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
        let child = ChildProfile(name: "Sam")
        let phone = Device(name: "Phone", kind: .phone, child: child)

        func session(year: Int = 2026, month: Int = 9, day: Int, minutes: Int) -> UsageSession {
            let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
            return UsageSession(startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)), child: child, device: phone)
        }

        let analysis = AnalysisCalculator.analyze(
            period: .week,
            now: now,
            childIDs: [child.id],
            sessions: [
                session(day: 14, minutes: 30),
                session(day: 15, minutes: 60),
                session(day: 17, minutes: 120),
                session(day: 7, minutes: 20),
                session(day: 8, minutes: 20),
                session(day: 9, minutes: 20),
                session(day: 10, minutes: 200)
            ],
            devices: [phone],
            calendar: calendar
        )

        #expect(analysis.currentMinutes == 90)
        #expect(analysis.previousMinutes == 60)
        #expect(analysis.dailyAverageMinutes == 30)
        #expect(analysis.changePercent == 50)
        #expect(analysis.dailyPoints.count == 3)
        #expect(analysis.devicePoints.first?.minutes == 90)
    }

    @Test("Analysis device breakdown is ordered by usage")
    func ordersAnalysisDeviceBreakdown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 12))!
        let child = ChildProfile(name: "Sam")
        let phone = Device(name: "Phone", kind: .phone, child: child)
        let tv = Device(name: "TV", kind: .television, child: child)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 9))!
        let analysis = AnalysisCalculator.analyze(
            period: .month,
            now: now,
            childIDs: [child.id],
            sessions: [
                UsageSession(startedAt: start, endedAt: start.addingTimeInterval(20 * 60), child: child, device: phone),
                UsageSession(startedAt: start.addingTimeInterval(2 * 60 * 60), endedAt: start.addingTimeInterval(2 * 60 * 60 + 40 * 60), child: child, device: tv)
            ],
            devices: [phone, tv],
            calendar: calendar
        )

        #expect(analysis.devicePoints.map(\.name) == ["TV", "Phone"])
    }
}
