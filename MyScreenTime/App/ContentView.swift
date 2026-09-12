import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var allChildren: [ChildProfile]
    @Query private var allUsageSessions: [UsageSession]

    let parent: ParentProfile

    @State private var isShowingSettings = false
    @State private var isAddingChild = false
    @State private var childToEdit: ChildProfile?
    @State private var childToArchive: ChildProfile?

    private var activeChildren: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id && $0.isActive }
    }

    private var archivedChildren: [ChildProfile] {
        allChildren.filter { $0.parent?.id == parent.id && !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    welcomeCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Children") {
                    if activeChildren.isEmpty {
                        ContentUnavailableView(
                            "No Children Yet",
                            systemImage: "figure.2.and.child.holdinghands",
                            description: Text("Add a child profile and choose their daily screen-time limit.")
                        )

                        Button("Add first child", systemImage: "plus.circle.fill") {
                            isAddingChild = true
                        }
                        .accessibilityIdentifier("add-child-button")
                    } else {
                        ForEach(activeChildren) { child in
                            childRow(child)
                                .swipeActions(edge: .trailing) {
                                    Button("Archive", systemImage: "archivebox") {
                                        childToArchive = child
                                    }
                                    .tint(AppTheme.warning)

                                    Button("Edit", systemImage: "pencil") {
                                        childToEdit = child
                                    }
                                    .tint(AppTheme.primary)
                                }
                        }

                        Button("Add child", systemImage: "plus") {
                            isAddingChild = true
                        }
                        .accessibilityIdentifier("add-child-button")
                    }
                }

                if !archivedChildren.isEmpty {
                    Section("Archived") {
                        ForEach(archivedChildren) { child in
                            HStack {
                                childRow(child)
                                Spacer()
                                Button("Restore") {
                                    restore(child)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MyScreenTime")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Add child", systemImage: "plus") {
                        isAddingChild = true
                    }

                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                ParentSettingsView(parent: parent)
            }
            .sheet(isPresented: $isAddingChild) {
                ChildFormView(parent: parent)
            }
            .sheet(
                isPresented: Binding(
                    get: { childToEdit != nil },
                    set: { if !$0 { childToEdit = nil } }
                )
            ) {
                if let childToEdit {
                    ChildFormView(parent: parent, child: childToEdit)
                }
            }
            .confirmationDialog(
                "Archive this child?",
                isPresented: Binding(
                    get: { childToArchive != nil },
                    set: { if !$0 { childToArchive = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Archive", role: .destructive) {
                    if let childToArchive {
                        archive(childToArchive)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their history will be kept, and you can restore the profile later.")
            }
        }
        .tint(AppTheme.primary)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome, \(parent.name)")
                .font(.title2.bold())

            if activeChildren.isEmpty {
                Text("Let’s set up your family.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(activeChildren.count) active child \(activeChildren.count == 1 ? "profile" : "profiles")")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func childRow(_ child: ChildProfile) -> some View {
        let summary = UsageAggregator.summary(on: .now, child: child, sessions: allUsageSessions)

        return NavigationLink {
            ChildDetailView(child: child)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(summary.statusText)
                        .font(.subheadline)
                        .foregroundStyle(statusColor(for: summary.status))

                    ProgressView(value: summary.progress)
                        .tint(statusColor(for: summary.status))
                        .accessibilityLabel("Daily screen-time progress")
                        .accessibilityValue("\(summary.usedMinutes) of \(summary.limitMinutes) minutes")
                }
            }
        }
        .accessibilityHint(child.isActive ? "Opens this child's devices" : "Opens archived child profile")
    }

    private func archive(_ child: ChildProfile) {
        child.isActive = false
        child.updatedAt = .now
        try? modelContext.save()
        childToArchive = nil
    }

    private func restore(_ child: ChildProfile) {
        child.isActive = true
        child.updatedAt = .now
        try? modelContext.save()
    }

    private func statusColor(for status: DailyLimitStatus) -> Color {
        switch status {
        case .normal: AppTheme.success
        case .nearLimit, .reached: AppTheme.warning
        case .exceeded: AppTheme.danger
        }
    }
}

#Preview {
    ContentView(parent: ParentProfile(name: "Taylor"))
        .modelContainer(
            for: [ParentProfile.self, ChildProfile.self, Device.self, UsageSession.self],
            inMemory: true
        )
}
