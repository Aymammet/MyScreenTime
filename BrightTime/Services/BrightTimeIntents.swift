import AppIntents
import Foundation

// Siri, Shortcuts and Spotlight actions:
// "Start a BrightTime timer for Emir", "Stop Emir's BrightTime timer",
// "How much time does Emir have left in BrightTime".

// MARK: - Entities

struct ChildEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kid"
    static let defaultQuery = ChildEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ChildEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ChildEntity] {
        await MainActor.run {
            AppServices.shared.allChildren()
                .filter { identifiers.contains($0.id) }
                .map { ChildEntity(id: $0.id, name: $0.name) }
        }
    }

    func entities(matching string: String) async throws -> [ChildEntity] {
        await MainActor.run {
            AppServices.shared.activeChildren()
                .filter { $0.name.localizedCaseInsensitiveContains(string) }
                .map { ChildEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [ChildEntity] {
        await MainActor.run {
            AppServices.shared.activeChildren().map { ChildEntity(id: $0.id, name: $0.name) }
        }
    }
}

struct DeviceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Device"
    static let defaultQuery = DeviceEntityQuery()

    let id: UUID
    let name: String
    let systemImage: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: systemImage))
    }
}

struct DeviceEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [DeviceEntity] {
        await MainActor.run {
            AppServices.shared.allDevices()
                .filter { identifiers.contains($0.id) }
                .map { DeviceEntity(id: $0.id, name: $0.name, systemImage: $0.kind.systemImage) }
        }
    }

    func entities(matching string: String) async throws -> [DeviceEntity] {
        await MainActor.run {
            AppServices.shared.allDevices()
                .filter { $0.isActive && $0.name.localizedCaseInsensitiveContains(string) }
                .map { DeviceEntity(id: $0.id, name: $0.name, systemImage: $0.kind.systemImage) }
        }
    }

    func suggestedEntities() async throws -> [DeviceEntity] {
        await MainActor.run {
            AppServices.shared.allDevices()
                .filter(\.isActive)
                .map { DeviceEntity(id: $0.id, name: $0.name, systemImage: $0.kind.systemImage) }
        }
    }
}

// MARK: - Errors

enum BrightTimeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case childNotFound
    case noDevice(String)
    case noTimer(String)
    case invalidMinutes

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .childNotFound:
            "I couldn't find that kid in BrightTime."
        case .noDevice(let name):
            "\(name) doesn't have a device yet. Add one in BrightTime first."
        case .noTimer(let name):
            "\(name) doesn't have a timer running."
        case .invalidMinutes:
            "Pick between 1 and 240 minutes."
        }
    }
}

// MARK: - Intents

struct StartScreenTimerIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Screen Timer"
    static let description = IntentDescription("Starts a BrightTime screen timer for a kid. The time is added to today's usage when it ends.")

    @Parameter(title: "Kid", requestValueDialog: "Which kid?")
    var child: ChildEntity

    @Parameter(title: "Minutes", requestValueDialog: "For how many minutes?")
    var minutes: Int

    @Parameter(title: "Device")
    var device: DeviceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer for \(\.$child)") {
            \.$device
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...240).contains(minutes) else { throw BrightTimeIntentError.invalidMinutes }
        let services = AppServices.shared
        services.completeDueTimers()

        guard let profile = services.child(id: child.id), profile.isActive else {
            throw BrightTimeIntentError.childNotFound
        }
        let available = services.devices(for: profile)
        let chosen = device.flatMap { wanted in available.first { $0.id == wanted.id } } ?? available.first
        guard let chosen else { throw BrightTimeIntentError.noDevice(profile.name) }

        let timer = services.timerManager.start(child: profile, device: chosen, minutes: minutes)
        let endTime = timer.endsAt.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Started \(minutes) minutes of \(chosen.name) time for \(profile.name). It ends at \(endTime).")
    }
}

struct StopScreenTimerIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Screen Timer"
    static let description = IntentDescription("Stops a kid's running BrightTime timer and saves the time used so far.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Kid", requestValueDialog: "Whose timer?")
    var child: ChildEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Stop the timer for \(\.$child)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        services.completeDueTimers()
        guard let timer = services.timerManager.timer(for: child.id) else {
            throw BrightTimeIntentError.noTimer(child.name)
        }
        let used = max(Int(min(Date.now, timer.endsAt).timeIntervalSince(timer.startedAt) / 60), 0)
        services.timerManager.stop(
            timer,
            children: services.allChildren(),
            devices: services.allDevices(),
            context: services.context
        )
        return .result(dialog: "Stopped \(child.name)'s \(timer.deviceName) timer after \(used) minutes.")
    }
}

struct TimeLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Screen Time Left"
    static let description = IntentDescription("Tells you how much screen time a kid has left today.")

    @Parameter(title: "Kid", requestValueDialog: "Which kid?")
    var child: ChildEntity

    static var parameterSummary: some ParameterSummary {
        Summary("How much time \(\.$child) has left")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        services.completeDueTimers()
        guard let profile = services.child(id: child.id) else { throw BrightTimeIntentError.childNotFound }

        let summary = services.todaySummary(for: profile)
        var sentence: String
        if summary.overMinutes > 0 {
            sentence = "\(profile.name) is \(TimeText.spoken(summary.overMinutes)) over today's limit."
        } else if summary.remainingMinutes == 0 {
            sentence = "\(profile.name) has used all of today's screen time."
        } else {
            sentence = "\(profile.name) has \(TimeText.spoken(summary.remainingMinutes)) left today."
        }
        if let timer = services.timerManager.timer(for: profile.id) {
            sentence += " A \(timer.deviceName) timer ends at \(timer.endsAt.formatted(date: .omitted, time: .shortened))."
        }
        if profile.bankBalance > 0 {
            sentence += " \(TimeText.spoken(profile.bankBalance)) is saved in the time bank."
        }
        return .result(dialog: "\(sentence)")
    }
}

// MARK: - App Shortcuts (work with Siri without any setup)

struct BrightTimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScreenTimerIntent(),
            phrases: [
                "Start a \(.applicationName) timer for \(\.$child)",
                "Start a screen timer for \(\.$child) in \(.applicationName)",
                "Start a \(.applicationName) timer",
            ],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StopScreenTimerIntent(),
            phrases: [
                "Stop the \(.applicationName) timer for \(\.$child)",
                "Stop \(\.$child)'s \(.applicationName) timer",
                "Stop a \(.applicationName) timer",
            ],
            shortTitle: "Stop Timer",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: TimeLeftIntent(),
            phrases: [
                "How much time does \(\.$child) have left in \(.applicationName)",
                "\(.applicationName) time left for \(\.$child)",
                "How much screen time is left in \(.applicationName)",
            ],
            shortTitle: "Time Left",
            systemImageName: "hourglass"
        )
    }
}
