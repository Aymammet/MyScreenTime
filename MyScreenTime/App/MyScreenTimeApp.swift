import SwiftData
import SwiftUI

@main
struct MyScreenTimeApp: App {
    private let modelContainer: ModelContainer

    init() {
        let isUITesting = CommandLine.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)

        do {
            modelContainer = try ModelContainer(
                for: ParentProfile.self,
                ChildProfile.self,
                Device.self,
                UsageSession.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create the MyScreenTime data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
