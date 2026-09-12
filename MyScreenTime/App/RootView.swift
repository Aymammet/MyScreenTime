import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \ParentProfile.createdAt) private var parentProfiles: [ParentProfile]

    var body: some View {
        if let parent = parentProfiles.first {
            ContentView(parent: parent)
        } else {
            ParentSetupView()
        }
    }
}
