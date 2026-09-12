import SwiftData
import SwiftUI

struct ChildFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allChildren: [ChildProfile]

    let parent: ParentProfile
    let child: ChildProfile?

    @State private var name: String
    @State private var dailyLimitMinutes: Int
    @State private var usesSchedule: Bool
    @State private var weekdayLimitMinutes: Int
    @State private var weekendLimitMinutes: Int
    @State private var saveErrorMessage: String?

    init(parent: ParentProfile, child: ChildProfile? = nil) {
        self.parent = parent
        self.child = child
        _name = State(initialValue: child?.name ?? "")
        _dailyLimitMinutes = State(initialValue: child?.dailyLimitMinutes ?? 120)
        _usesSchedule = State(initialValue: child?.weekdayLimitMinutes != nil && child?.weekendLimitMinutes != nil)
        _weekdayLimitMinutes = State(initialValue: child?.weekdayLimitMinutes ?? child?.dailyLimitMinutes ?? 120)
        _weekendLimitMinutes = State(initialValue: child?.weekendLimitMinutes ?? child?.dailyLimitMinutes ?? 120)
    }

    private var normalizedName: String {
        ChildProfile.normalizedName(name)
    }

    private var hasDuplicateName: Bool {
        allChildren.contains { candidate in
            candidate.parent?.id == parent.id
                && candidate.id != child?.id
                && candidate.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    private var isValid: Bool {
        ChildProfile.isValidName(name)
            && ChildProfile.isValidDailyLimit(dailyLimitMinutes)
            && (!usesSchedule || (
                ChildProfile.isValidDailyLimit(weekdayLimitMinutes)
                    && ChildProfile.isValidDailyLimit(weekendLimitMinutes)
            ))
            && !hasDuplicateName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Child's name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("child-name-field")

                    if !name.isEmpty, !ChildProfile.isValidName(name) {
                        validationMessage("Enter a name between 2 and 50 characters.")
                    } else if hasDuplicateName {
                        validationMessage("A child with this name already exists.")
                    }
                } header: {
                    Text("Child profile")
                }

                Section {
                    Toggle("Different weekend limit", isOn: $usesSchedule)
                        .accessibilityIdentifier("weekend-limit-toggle")

                    if usesSchedule {
                        limitStepper("Weekday limit", value: $weekdayLimitMinutes)
                            .accessibilityIdentifier("weekday-limit-stepper")
                        limitStepper("Weekend limit", value: $weekendLimitMinutes)
                            .accessibilityIdentifier("weekend-limit-stepper")
                    } else {
                        limitStepper("Daily limit", value: $dailyLimitMinutes)
                            .accessibilityIdentifier("daily-limit-stepper")
                    }
                } footer: {
                    Text(usesSchedule
                         ? "Weekday limits apply Monday through Friday; weekend limits apply Saturday and Sunday."
                         : "This limit applies every day to the child's combined use across all devices.")
                }
            }
            .navigationTitle(child == nil ? "Add Child" : "Edit Child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChild()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("save-child-profile")
                }
            }
            .alert(
                "Couldn’t Save Child",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK") {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "Please try again.")
            }
        }
    }

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.danger)
    }

    private func formattedLimit(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private func limitStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 15...1_440, step: 15) {
            LabeledContent(title, value: formattedLimit(value.wrappedValue))
        }
    }

    private func saveChild() {
        if let child {
            child.name = normalizedName
            child.dailyLimitMinutes = dailyLimitMinutes
            child.weekdayLimitMinutes = usesSchedule ? weekdayLimitMinutes : nil
            child.weekendLimitMinutes = usesSchedule ? weekendLimitMinutes : nil
            child.updatedAt = .now
        } else {
            modelContext.insert(
                ChildProfile(
                    name: normalizedName,
                    dailyLimitMinutes: dailyLimitMinutes,
                    weekdayLimitMinutes: usesSchedule ? weekdayLimitMinutes : nil,
                    weekendLimitMinutes: usesSchedule ? weekendLimitMinutes : nil,
                    parent: parent
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}
