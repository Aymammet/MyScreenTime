import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import Security
import SwiftUI

/// Keeps the parent area behind a passcode (and optionally Face ID), so kids can't
/// raise their own limits or stop timers. All data stays on the device; "Sign Out"
/// simply locks the app until the parent unlocks it again.
@MainActor
@Observable
final class AppLock {
    enum AutoLock: String, CaseIterable, Identifiable {
        case immediately
        case afterOneMinute
        case afterFiveMinutes
        case never

        var id: String { rawValue }

        var title: String {
            switch self {
            case .immediately: "When app closes"
            case .afterOneMinute: "After 1 minute"
            case .afterFiveMinutes: "After 5 minutes"
            case .never: "Never"
            }
        }

        var delay: TimeInterval? {
            switch self {
            case .immediately: 0
            case .afterOneMinute: 60
            case .afterFiveMinutes: 300
            case .never: nil
            }
        }
    }

    enum Biometry {
        case none, faceID, touchID, opticID

        var name: String {
            switch self {
            case .none: "Biometrics"
            case .faceID: "Face ID"
            case .touchID: "Touch ID"
            case .opticID: "Optic ID"
            }
        }

        var systemImage: String {
            switch self {
            case .touchID: "touchid"
            case .opticID: "opticid"
            default: "faceid"
            }
        }
    }

    /// Why the app is locked. Face ID is only offered automatically after an
    /// automatic lock; after a deliberate Sign Out the parent has to tap Unlock,
    /// otherwise their own face would undo the sign-out instantly.
    enum LockReason: String {
        case manual
        case automatic
    }

    private enum Keys {
        /// Same key the first sign-out build used, so a signed-out app stays locked.
        static let isLocked = "brighttime.parentIsSignedOut"
        static let lockReason = "brighttime.lock.reason"
        static let useBiometrics = "brighttime.lock.biometrics"
        static let autoLock = "brighttime.lock.autoLock"
        static let backgroundedAt = "brighttime.lock.backgroundedAt"
        static let failedAttempts = "brighttime.lock.failedAttempts"
        static let cooldownStart = "brighttime.lock.cooldownStart"
        static let cooldownUptime = "brighttime.lock.cooldownUptime"
        static let cooldownSeconds = "brighttime.lock.cooldownSeconds"
    }

    static let passcodeLength = 4
    private static let maxAttemptsBeforeCooldown = 5

    private let defaults = UserDefaults.standard
    private let isUITesting = CommandLine.arguments.contains("-ui-testing")

    private(set) var isLocked: Bool
    private(set) var lockReason: LockReason
    private(set) var hasPasscode: Bool

    var useBiometrics: Bool {
        didSet { defaults.set(useBiometrics, forKey: Keys.useBiometrics) }
    }

    var autoLock: AutoLock {
        didSet { defaults.set(autoLock.rawValue, forKey: Keys.autoLock) }
    }

    init() {
        // Locals only until every stored property is set.
        let defaults = UserDefaults.standard
        let uiTesting = CommandLine.arguments.contains("-ui-testing")
        let passcodeExists = PasscodeStore.exists()
        hasPasscode = passcodeExists
        useBiometrics = defaults.object(forKey: Keys.useBiometrics) as? Bool ?? true
        let autoLockSetting = defaults.string(forKey: Keys.autoLock).flatMap(AutoLock.init(rawValue:)) ?? .immediately
        autoLock = autoLockSetting
        lockReason = defaults.string(forKey: Keys.lockReason).flatMap(LockReason.init(rawValue:)) ?? .manual

        var locked = defaults.bool(forKey: Keys.isLocked)
        // Cold launch after the app was closed (or killed) in the background:
        // apply auto-lock here, because no "became active" change arrives.
        let leftAt = defaults.double(forKey: Keys.backgroundedAt)
        if !locked, passcodeExists, leftAt > 0, let delay = autoLockSetting.delay,
           Date.now.timeIntervalSince1970 - leftAt >= delay {
            locked = true
            lockReason = .automatic
            defaults.set(true, forKey: Keys.isLocked)
            defaults.set(LockReason.automatic.rawValue, forKey: Keys.lockReason)
        }
        defaults.removeObject(forKey: Keys.backgroundedAt)
        isLocked = locked && !uiTesting
    }

    /// Re-reads the Keychain (e.g. when the app becomes active).
    func refresh() {
        hasPasscode = PasscodeStore.exists()
    }

    // MARK: - Biometrics

    /// The biometric hardware this iPhone has, whether or not it's set up yet.
    /// (`biometryType` is filled in by `canEvaluatePolicy` even when it fails.)
    var biometry: Biometry {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    /// True when Face ID / Touch ID is set up in iPhone Settings.
    var isBiometryEnrolled: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Whether to offer "Unlock with Face ID" next to the passcode.
    var offersBiometrics: Bool {
        hasPasscode && useBiometrics && biometry != .none
    }

    /// Whether Face ID can actually run right now.
    var canUseBiometrics: Bool {
        offersBiometrics && isBiometryEnrolled
    }

    /// Face ID pops up on its own only after an automatic lock.
    var shouldAutoPromptBiometrics: Bool {
        isLocked && lockReason == .automatic && canUseBiometrics
    }

    /// Shows the system Face ID / Touch ID prompt. Unlocks on success.
    @discardableResult
    func unlockWithBiometrics() async -> Bool {
        guard await verifyWithBiometrics() else { return false }
        unlock()
        return true
    }

    /// Face ID / Touch ID check without unlocking (e.g. before Reset).
    func verifyWithBiometrics() async -> Bool {
        guard canUseBiometrics else { return false }
        let success = await Self.evaluateBiometrics()
        if success { resetFailures() }
        return success
    }

    /// Runs off the main actor so the non-Sendable `LAContext` never crosses actors.
    nonisolated private static func evaluateBiometrics() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock BrightTime to manage your family's screen time."
            )
        } catch {
            return false
        }
    }

    // MARK: - Passcode

    enum PasscodeCheck: Equatable {
        case correct
        case wrong(attemptsLeft: Int)
        case coolingDown(until: Date)
    }

    /// Saves a new passcode. Returns false (and changes nothing) if the Keychain
    /// refuses it, so the app never locks with a code that can't be checked.
    @discardableResult
    func setPasscode(_ code: String) -> Bool {
        guard PasscodeStore.save(code) else { return false }
        hasPasscode = true
        resetFailures()
        return true
    }

    func removePasscode() {
        PasscodeStore.delete()
        hasPasscode = PasscodeStore.exists()
        unlock()
    }

    /// When the current cooldown ends, if one is running. Measured with the
    /// device's uptime as well as the clock, so changing the time doesn't end it.
    var lockedOutUntil: Date? {
        let seconds = defaults.double(forKey: Keys.cooldownSeconds)
        guard seconds > 0 else { return nil }
        let startedUptime = defaults.double(forKey: Keys.cooldownUptime)
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed: TimeInterval
        if uptime >= startedUptime {
            elapsed = uptime - startedUptime
        } else {
            // The phone restarted since; fall back to the wall clock.
            elapsed = Date.now.timeIntervalSince1970 - defaults.double(forKey: Keys.cooldownStart)
        }
        let remaining = seconds - max(elapsed, 0)
        return remaining > 0 ? Date.now.addingTimeInterval(remaining) : nil
    }

    /// Checks a passcode, with a cooldown after repeated wrong guesses so a child
    /// can't simply try every combination.
    func check(_ code: String) -> PasscodeCheck {
        if let until = lockedOutUntil {
            return .coolingDown(until: until)
        }
        guard PasscodeStore.matches(code) else {
            let failures = defaults.integer(forKey: Keys.failedAttempts) + 1
            defaults.set(failures, forKey: Keys.failedAttempts)
            PasscodeAlerts.recordFailure(count: failures)
            if failures % Self.maxAttemptsBeforeCooldown == 0 {
                // 1 minute, then 5, then 15 on further rounds of wrong guesses.
                let round = failures / Self.maxAttemptsBeforeCooldown
                let minutes = [1, 5, 15][min(round - 1, 2)]
                defaults.set(Double(minutes * 60), forKey: Keys.cooldownSeconds)
                defaults.set(ProcessInfo.processInfo.systemUptime, forKey: Keys.cooldownUptime)
                defaults.set(Date.now.timeIntervalSince1970, forKey: Keys.cooldownStart)
                return .coolingDown(until: Date.now.addingTimeInterval(TimeInterval(minutes * 60)))
            }
            return .wrong(attemptsLeft: Self.maxAttemptsBeforeCooldown - failures % Self.maxAttemptsBeforeCooldown)
        }
        resetFailures()
        return .correct
    }

    private func resetFailures() {
        PasscodeAlerts.endRun()
        for key in [Keys.failedAttempts, Keys.cooldownSeconds, Keys.cooldownUptime, Keys.cooldownStart] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Locking

    /// Locks the parent area. Only meaningful once a passcode exists.
    func lock(reason: LockReason = .manual) {
        guard hasPasscode, !isUITesting else { return }
        lockReason = reason
        isLocked = true
        defaults.set(true, forKey: Keys.isLocked)
        defaults.set(reason.rawValue, forKey: Keys.lockReason)
    }

    func unlock() {
        isLocked = false
        defaults.set(false, forKey: Keys.isLocked)
        defaults.removeObject(forKey: Keys.backgroundedAt)
        resetFailures()
    }

    /// Auto-lock. "When app closes" locks as the app leaves the screen, so the app
    /// switcher never shows the dashboard; timed options lock on return.
    func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard hasPasscode, !isLocked else { return }
            if autoLock == .immediately {
                lock(reason: .automatic)
            } else {
                defaults.set(Date.now.timeIntervalSince1970, forKey: Keys.backgroundedAt)
            }
        case .active:
            refresh()
            let left = defaults.double(forKey: Keys.backgroundedAt)
            defaults.removeObject(forKey: Keys.backgroundedAt)
            guard left > 0, hasPasscode, !isLocked, let delay = autoLock.delay else { return }
            if Date.now.timeIntervalSince1970 - left >= delay {
                lock(reason: .automatic)
            }
        default:
            break
        }
    }

    /// Clears the lock and passcode as part of "Reset BrightTime" or a fresh setup.
    func eraseAll() {
        PasscodeStore.delete()
        hasPasscode = false
        for key in [Keys.isLocked, Keys.lockReason, Keys.useBiometrics, Keys.autoLock, Keys.backgroundedAt] {
            defaults.removeObject(forKey: key)
        }
        resetFailures()
        isLocked = false
        lockReason = .manual
        useBiometrics = true
        autoLock = .immediately
    }
}

// MARK: - Keychain storage

/// Stores a salted SHA-256 hash of the passcode in the Keychain (never the code
/// itself), available only on this device.
private enum PasscodeStore {
    private static let service = "com.karasandlabs.BrightTime.parentPasscode"
    private static let account = "parent"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Adds or replaces the stored passcode. Returns whether it was saved; the old
    /// one is only replaced once the new one is accepted.
    static func save(_ code: String) -> Bool {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { return false }
        let salt = Data(saltBytes)
        let record = Data((salt.base64EncodedString() + ":" + hash(code, salt: salt).base64EncodedString()).utf8)

        var addQuery = baseQuery
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData as String] = record
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess { return true }
        guard status == errSecDuplicateItem else { return false }

        let update: [String: Any] = [kSecValueData as String: record]
        return SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecSuccess
    }

    /// True when a passcode is stored. Only "not found" counts as no passcode,
    /// so a temporary Keychain error can't silently switch protection off.
    static func exists() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status != errSecItemNotFound
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func matches(_ code: String) -> Bool {
        guard let record = read() else { return false }
        let parts = record.split(separator: ":").map(String.init)
        guard parts.count == 2,
              let salt = Data(base64Encoded: parts[0]),
              let stored = Data(base64Encoded: parts[1]) else { return false }
        return hash(code, salt: salt) == stored
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static func hash(_ code: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(code.utf8)))
    }
}
