import SwiftData
import SwiftUI

// MARK: - Time bank card (child detail)

/// Earned minutes waiting to be used, with quick "Earn" and "Use" actions.
struct TimeBankCard: View {
    @Environment(\.modelContext) private var modelContext
    let child: ChildProfile

    @State private var isEarning = false
    @State private var isUsing = false

    private var recentCredits: [TimeCredit] {
        child.timeCredits.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        let balance = child.bankBalance
        let bonusToday = child.bonusMinutes(on: .now)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.warningTint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time bank")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryDeep)
                    Text("Earned with chores, reading and more")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TimeText.compact(balance))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("time-bank-balance")
                    Text("saved")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            if bonusToday > 0 {
                BrightChip(text: "+\(TimeText.compact(bonusToday)) added to today", systemImage: "plus.circle.fill")
            }

            HStack(spacing: 10) {
                Button {
                    isEarning = true
                } label: {
                    Label("Earn time", systemImage: "plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.primary, in: Capsule())
                }
                .accessibilityIdentifier("earn-time-button")

                Button {
                    isUsing = true
                } label: {
                    Label("Use time", systemImage: "arrow.down.to.line")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.primaryTint, in: Capsule())
                }
                .disabled(balance == 0)
                .opacity(balance == 0 ? 0.45 : 1)
                .accessibilityIdentifier("use-time-button")
            }
            .buttonStyle(.plain)

            if !recentCredits.isEmpty {
                VStack(spacing: 0) {
                    ForEach(recentCredits.prefix(3)) { credit in
                        TimeCreditRow(credit: credit)
                            .padding(.vertical, 6)
                    }
                }
                if recentCredits.count > 3 {
                    NavigationLink {
                        TimeBankHistoryView(child: child)
                    } label: {
                        HStack {
                            Text("See all")
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .animation(AppTheme.spring, value: balance)
        .sheet(isPresented: $isEarning) {
            EarnTimeSheet(child: child)
        }
        .sheet(isPresented: $isUsing) {
            UseTimeSheet(child: child)
        }
    }
}

struct TimeCreditRow: View {
    let credit: TimeCredit

    var body: some View {
        let isEarned = credit.kind == .earned

        HStack(spacing: 10) {
            Image(systemName: isEarned ? credit.symbol : "arrow.down.to.line")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isEarned ? AppTheme.warning : AppTheme.primary)
                .frame(width: 30, height: 30)
                .background((isEarned ? AppTheme.warningTint : AppTheme.primaryTint), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(isEarned ? credit.title : "Added to \(dayName(credit.day))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .lineLimit(1)
                Text(credit.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            Text("\(isEarned ? "+" : "−")\(TimeText.compact(credit.minutes))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(isEarned ? AppTheme.warningText : AppTheme.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func dayName(_ date: Date) -> String {
        let calendar = AppCalendar.day
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - Earn

struct EarnTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<EarnActivity> { $0.isActive }, sort: \EarnActivity.sortOrder)
    private var activities: [EarnActivity]

    let child: ChildProfile

    @State private var selectedID: UUID?
    @State private var isCustom = false
    @State private var customName = ""
    @State private var customMinutes = 15
    @State private var didEarn = false

    private var selected: EarnActivity? {
        activities.first { $0.id == selectedID }
    }

    private var minutesToAdd: Int {
        isCustom ? customMinutes : (selected?.minutes ?? 0)
    }

    private var canAdd: Bool {
        isCustom ? !customName.trimmingCharacters(in: .whitespaces).isEmpty : selected != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What did \(child.name) do?")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.primaryDeep)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(activities) { activity in
                            activityTile(
                                name: activity.name,
                                symbol: activity.symbol,
                                minutes: activity.minutes,
                                isSelected: !isCustom && selectedID == activity.id
                            ) {
                                isCustom = false
                                selectedID = activity.id
                            }
                        }
                        activityTile(name: "Something else", symbol: "sparkles", minutes: nil, isSelected: isCustom) {
                            isCustom = true
                            selectedID = nil
                        }
                    }

                    if isCustom {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("What was it?", text: $customName)
                                .textInputAutocapitalization(.sentences)
                                .padding(12)
                                .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onChange(of: customName) { _, value in
                                    customName = String(value.prefix(EarnActivity.maximumNameLength))
                                }
                            Stepper(value: $customMinutes, in: 5...120, step: 5) {
                                LabeledContent("Minutes earned", value: TimeText.compact(customMinutes))
                            }
                        }
                        .brightCard(padding: 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("Earned minutes go into \(child.name)'s time bank. Use them on any day to add to that day's limit.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(16)
                .animation(AppTheme.spring, value: isCustom)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    earn()
                } label: {
                    Text(canAdd ? "Add +\(TimeText.compact(minutesToAdd)) to \(child.name)'s bank" : "Pick an activity")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("confirm-earn-time")
            }
            .navigationTitle("Earn time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Edit") {
                        EarnActivitiesView()
                    }
                }
            }
            .task {
                EarnActivity.seedStarterSetIfNeeded(in: modelContext)
            }
            .sensoryFeedback(.success, trigger: didEarn)
        }
    }

    private func activityTile(
        name: String,
        symbol: String,
        minutes: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.primary)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? AppTheme.primary : AppTheme.primaryTint, in: Circle())
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryDeep)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(minutes.map { "+\(TimeText.compact($0))" } ?? "Choose minutes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(minutes == nil ? AppTheme.textSecondary : AppTheme.warningText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AppTheme.primary : AppTheme.cardBorder, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func earn() {
        guard canAdd else { return }
        let credit: TimeCredit
        if isCustom {
            credit = TimeCredit(
                kind: .earned,
                minutes: customMinutes,
                title: customName.trimmingCharacters(in: .whitespaces),
                symbol: "sparkles",
                child: child
            )
        } else if let selected {
            credit = TimeCredit(kind: .earned, minutes: selected.minutes, title: selected.name, symbol: selected.symbol, child: child)
        } else {
            return
        }
        modelContext.insert(credit)
        child.updatedAt = .now
        try? modelContext.save()
        didEarn.toggle()
        dismiss()
    }
}

extension EarnActivity {
    private static let seededKey = "brighttime.bank.seeded"

    /// Adds the starter activities once. Their ids are fixed, so two co-parents
    /// seeding on separate iPhones end up with the same list, not duplicates.
    @MainActor
    static func seedStarterSetIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        let existing = Set(((try? context.fetch(FetchDescriptor<EarnActivity>())) ?? []).map(\.id))
        for (index, item) in starterSet.enumerated() {
            let id = UUID(uuidString: String(format: "6B1E5A70-0000-4000-8000-%012d", index + 1)) ?? UUID()
            guard !existing.contains(id) else { continue }
            context.insert(EarnActivity(id: id, name: item.name, symbol: item.symbol, minutes: item.minutes, sortOrder: index))
        }
        try? context.save()
    }
}

// MARK: - Use

struct UseTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let child: ChildProfile

    @State private var minutes = 15
    @State private var didUse = false

    private var balance: Int { child.bankBalance }

    private var quickChoices: [Int] {
        [15, 30, 45, 60].filter { $0 < balance }
    }

    var body: some View {
        let currentLimit = child.limitMinutes(on: .now)

        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Text(TimeText.compact(balance))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryDeep)
                        Text("in \(child.name)'s time bank")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickChoices, id: \.self) { choice in
                                chip(TimeText.compact(choice), isSelected: minutes == choice) { minutes = choice }
                            }
                            chip("All \(TimeText.compact(balance))", isSelected: minutes == balance) { minutes = balance }
                        }
                        .padding(.vertical, 2)
                    }
                    Stepper(value: $minutes, in: min(5, balance)...max(balance, 1), step: 5) {
                        LabeledContent("Add", value: TimeText.compact(minutes))
                    }
                } header: {
                    Text("Add to today's limit")
                } footer: {
                    Text("Today's limit goes from \(TimeText.compact(currentLimit)) to \(TimeText.compact(currentLimit + minutes)).")
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Use time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { use() }
                        .fontWeight(.semibold)
                        .disabled(minutes <= 0 || minutes > balance)
                        .accessibilityIdentifier("confirm-use-time")
                }
            }
            .onAppear {
                minutes = min(15, balance)
            }
            .sensoryFeedback(.success, trigger: didUse)
        }
        .presentationDetents([.medium, .large])
    }

    private func chip(_ text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.bold())
                .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.primary : AppTheme.primaryTint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func use() {
        let amount = min(minutes, balance)
        guard amount > 0 else { return }
        modelContext.insert(TimeCredit(
            kind: .used,
            minutes: amount,
            title: "Added to today",
            symbol: "arrow.down.to.line",
            day: .now,
            child: child
        ))
        child.updatedAt = .now
        try? modelContext.save()
        didUse.toggle()
        dismiss()
    }
}

// MARK: - History

struct TimeBankHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let child: ChildProfile

    @State private var creditToDelete: TimeCredit?

    private var credits: [TimeCredit] {
        child.timeCredits.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                ForEach(credits) { credit in
                    TimeCreditRow(credit: credit)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash") {
                                creditToDelete = credit
                            }
                            .tint(AppTheme.danger)
                        }
                }
            } footer: {
                Text("Deleting an entry changes the bank balance and, for time that was used, that day's limit.")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Time bank")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { creditToDelete != nil }, set: { if !$0 { creditToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let creditToDelete {
                    modelContext.delete(creditToDelete)
                    try? modelContext.save()
                }
                creditToDelete = nil
            }
        }
    }
}

// MARK: - Activities editor

struct EarnActivitiesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EarnActivity.sortOrder) private var allActivities: [EarnActivity]

    @State private var activityToEdit: EarnActivity?
    @State private var isAdding = false

    private var activities: [EarnActivity] { allActivities.filter(\.isActive) }

    var body: some View {
        List {
            Section {
                ForEach(activities) { activity in
                    Button {
                        activityToEdit = activity
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: activity.symbol)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 32, height: 32)
                                .background(AppTheme.primaryTint, in: Circle())
                            Text(activity.name)
                                .foregroundStyle(AppTheme.primaryDeep)
                            Spacer()
                            Text("+\(TimeText.compact(activity.minutes))")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.warningText)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        activities[index].isActive = false
                        activities[index].updatedAt = .now
                    }
                    try? modelContext.save()
                }
                .onMove { source, destination in
                    var reordered = activities
                    reordered.move(fromOffsets: source, toOffset: destination)
                    for (index, activity) in reordered.enumerated() where activity.sortOrder != index {
                        activity.sortOrder = index
                        activity.updatedAt = .now
                    }
                    try? modelContext.save()
                }

                Button("Add activity", systemImage: "plus") {
                    isAdding = true
                }
            } footer: {
                Text("Kids earn these minutes into their time bank. Past entries keep their name and minutes if you change or remove an activity.")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Earn-time activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .task { EarnActivity.seedStarterSetIfNeeded(in: modelContext) }
        .sheet(isPresented: $isAdding) {
            EarnActivityForm(activity: nil, nextSortOrder: (activities.map(\.sortOrder).max() ?? -1) + 1)
        }
        .sheet(item: $activityToEdit) { activity in
            EarnActivityForm(activity: activity, nextSortOrder: activity.sortOrder)
        }
    }
}

struct EarnActivityForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let activity: EarnActivity?
    let nextSortOrder: Int

    @State private var name: String
    @State private var minutes: Int
    @State private var symbol: String

    init(activity: EarnActivity?, nextSortOrder: Int) {
        self.activity = activity
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: activity?.name ?? "")
        _minutes = State(initialValue: activity?.minutes ?? 15)
        _symbol = State(initialValue: activity?.symbol ?? "star.fill")
    }

    private var isValid: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Activity name", text: $name)
                        .onChange(of: name) { _, value in
                            name = String(value.prefix(EarnActivity.maximumNameLength))
                        }
                    Stepper(value: $minutes, in: 5...120, step: 5) {
                        LabeledContent("Earns", value: "+\(TimeText.compact(minutes))")
                    }
                }
                .listRowBackground(AppTheme.surface)

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(EarnActivity.symbolChoices, id: \.self) { choice in
                            Button {
                                symbol = choice
                            } label: {
                                Image(systemName: choice)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(symbol == choice ? AppTheme.onPrimary : AppTheme.primary)
                                    .frame(width: 40, height: 40)
                                    .background(symbol == choice ? AppTheme.primary : AppTheme.primaryTint, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice)
                            .accessibilityAddTraits(symbol == choice ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(activity == nil ? "New activity" : "Edit activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let activity {
            activity.name = trimmed
            activity.minutes = minutes
            activity.symbol = symbol
            activity.updatedAt = .now
        } else {
            modelContext.insert(EarnActivity(name: trimmed, symbol: symbol, minutes: minutes, sortOrder: nextSortOrder))
        }
        try? modelContext.save()
        dismiss()
    }
}
