import SwiftData
import SwiftUI

@main
struct BrightTimeApp: App {
    @UIApplicationDelegateAdaptor(BrightTimeAppDelegate.self) private var appDelegate
    @State private var appLock = AppLock()
    @State private var familySync = FamilySync.shared
    @StateObject private var timerManager = AppServices.shared.timerManager

    init() {
        AppCalendar.apply()
        AppNotifications.shared.configure()
        if !AppServices.shared.isUITesting {
            FamilySync.shared.start(with: AppServices.shared.modelContainer)
        }
        BrightTimeShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appLock)
                .environment(familySync)
                .environmentObject(timerManager)
        }
        .modelContainer(AppServices.shared.modelContainer)
    }
}
