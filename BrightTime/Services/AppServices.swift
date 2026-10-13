import SwiftData
import SwiftUI

/// The app's long-lived objects, shared by the UI, Siri / Shortcuts intents and
/// iCloud family sync, so they all see the same data and timers.
@MainActor
final class AppServices {
    static let shared = AppServices()

    static let modelTypes: [any PersistentModel.Type] = [
        ParentProfile.self,
        ChildProfile.self,
        Device.self,
        UsageSession.self,
        EarnActivity.self,
        TimeCredit.self,
        TimeRequest.self,
        PasscodeAlert.self,
    ]

    let modelContainer: ModelContainer
    let timerManager: ScreenTimerManager
    let isUITesting: Bool

    var context: ModelContext { modelContainer.mainContext }

    private init() {
        isUITesting = CommandLine.arguments.contains("-ui-testing")
        let schema = Schema(Self.modelTypes)
        // Keep the store where it has always been, and local-only: the app now has
        // iCloud and App Group entitlements, which SwiftData would otherwise use to
        // move the store and turn on its own CloudKit mirroring. Co-parent sync is
        // done by FamilySync instead.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isUITesting,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Unable to create the BrightTime data store: \(error)")
        }
        timerManager = ScreenTimerManager()
    }

    // MARK: - Lookups used by intents

    func activeChildren() -> [ChildProfile] {
        let descriptor = FetchDescriptor<ChildProfile>(sortBy: [SortDescriptor(\.createdAt)])
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isActive)
    }

    func allChildren() -> [ChildProfile] {
        (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
    }

    func allDevices() -> [Device] {
        (try? context.fetch(FetchDescriptor<Device>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func child(id: UUID) -> ChildProfile? {
        allChildren().first { $0.id == id }
    }

    /// Devices a child can use, their own first.
    func devices(for child: ChildProfile) -> [Device] {
        allDevices()
            .filter { $0.isActive && $0.isAvailable(to: child.id) }
            .sorted { lhs, rhs in
                if lhs.isShared != rhs.isShared { return !lhs.isShared }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func todaySummary(for child: ChildProfile) -> DailyUsageSummary {
        let calendar = AppCalendar.day
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .now
        let descriptor = FetchDescriptor<UsageSession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        return UsageAggregator.summary(on: .now, child: child, sessions: sessions)
    }

    /// Records any finished timers (intents can run while no screen is open).
    func completeDueTimers() {
        timerManager.completeDueTimers(children: allChildren(), devices: allDevices(), context: context)
    }
}
