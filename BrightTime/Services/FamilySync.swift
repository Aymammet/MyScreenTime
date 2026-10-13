@preconcurrency import CloudKit
import Foundation
import Observation
import os
import SwiftData
import UIKit

private let syncLog = Logger(subsystem: "com.karasandlabs.BrightTime", category: "FamilySync")

/// Shares one family between co-parents through iCloud.
///
/// The parent who invites ("owner") keeps the family in a custom zone of their
/// private iCloud database and shares the whole zone with a `CKShare`. A co-parent
/// who accepts ("member") syncs the same zone through their shared database.
/// `CKSyncEngine` moves the changes; this class maps records to SwiftData models.
///
/// Local changes are found by comparing a fingerprint of every record with the
/// fingerprint last synced, so no screen has to report its edits.
/// Not synced: parent profiles, passcodes, app settings and running timers (a
/// timer's time is shared once it finishes and becomes a usage session).
@MainActor
@Observable
final class FamilySync {
    static let shared = FamilySync()
    static let containerID = "iCloud.com.karasandlabs.BrightTime"
    static let zoneName = "BrightTimeFamily"

    enum Role: String, Codable {
        case none, owner, member
    }

    enum Status: Equatable {
        case idle
        case working(String)
        case synced(Date)
        case failed(String)
    }

    struct Participant: Identifiable, Hashable {
        let id: String
        let name: String
        let isOwner: Bool
        let isAccepted: Bool
    }

    private(set) var role: Role = .none
    private(set) var status: Status = .idle
    private(set) var participants: [Participant] = []
    private(set) var ownerName: String?

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    @ObservationIgnored private var store = SyncStore()
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var cloudContainer: CKContainer?
    @ObservationIgnored private var scanLoop: Task<Void, Never>?
    @ObservationIgnored private var sharingDelegate: SharingControllerDelegate?
    /// Records per upload. Halved when iCloud says a request was too large.
    @ObservationIgnored private var batchLimit = 50
    /// True when the current upload round had items iCloud rejected.
    @ObservationIgnored private var uploadRoundFailed = false
    /// Requests that are new or changed status in the batch being applied.
    @ObservationIgnored private var arrivedRequests: [TimeRequest] = []
    /// Wrong-passcode alerts that are new or have more tries in this batch.
    @ObservationIgnored private var arrivedAlerts: [PasscodeAlert] = []

    private init() {}

    // MARK: - Lifecycle

    /// Call once at launch.
    func start(with container: ModelContainer) {
        modelContainer = container
        store = SyncStore.load()
        role = store.role
        ownerName = store.ownerDisplayName
        if role != .none {
            makeEngine()
        }
    }

    func sceneBecameActive() {
        guard engine != nil else { return }
        scanLocalChanges()
        Task { await syncNow(quiet: true) }
        scanLoop?.cancel()
        scanLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.scanLocalChanges()
            }
        }
    }

    func sceneWentToBackground() {
        scanLoop?.cancel()
        scanLoop = nil
        guard let engine else { return }
        scanLocalChanges()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "BrightTime family sync")
        Task {
            try? await engine.sendChanges()
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    /// Scans for local edits, then fetches and sends right away.
    func syncNow(quiet: Bool = false) async {
        guard let engine else { return }
        if !quiet { status = .working("Syncing…") }
        scanLocalChanges()
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            if case .failed = status {} else { status = .synced(.now) }
        } catch {
            syncLog.error("Sync failed: \(String(describing: error), privacy: .public)")
            if !quiet { status = .failed(Self.message(for: error)) }
        }
        if role == .owner { await refreshParticipants() }
    }

    // MARK: - Owner: invite

    func inviteCoParent() async {
        guard role != .member else { return }
        status = .working("Preparing your invite…")
        let isFirstInvite = role == .none
        do {
            try await requireAccount()
            // Make the family's zone and its share straight away, so the invite
            // never waits on uploading the whole history. The data follows in the
            // background, and any upload problem shows up on this screen.
            try await ensureZone()
            let share = try await fetchOrCreateShare()
            if isFirstInvite {
                store = SyncStore()
                store.role = .owner
                role = .owner
                store.save()
                makeEngine()
                scanLocalChanges()
            }
            status = .synced(.now)
            presentSharingController(for: share)
            Task { await self.syncNow() }
        } catch {
            syncLog.error("Invite failed: \(String(describing: error), privacy: .public)")
            // Don't leave a half-set-up share behind if the very first try fails.
            if isFirstInvite { resetLocalState() }
            status = .failed(Self.message(for: error))
        }
    }

    /// Shows Apple's sheet for adding or removing people.
    func manageParticipants() async {
        guard role == .owner else { return }
        do {
            let share = try await fetchOrCreateShare()
            presentSharingController(for: share)
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    func refreshParticipants() async {
        guard role == .owner else {
            participants = []
            return
        }
        guard let share = try? await existingShare() else {
            participants = []
            return
        }
        participants = share.participants.compactMap { participant in
            guard participant.acceptanceStatus != .removed else { return nil }
            return Participant(
                id: participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                name: Self.displayName(of: participant.userIdentity) ?? (participant.role == .owner ? "You" : "Invited person"),
                isOwner: participant.role == .owner,
                isAccepted: participant.acceptanceStatus == .accepted
            )
        }
    }

    // MARK: - Member: accept

    func accept(_ metadata: CKShare.Metadata) async {
        guard metadata.share.recordID.zoneID.zoneName == Self.zoneName else { return }
        if role == .owner {
            status = .failed("You're already sharing your own family. Stop sharing first, then open the invite again.")
            return
        }
        status = .working("Joining the family…")
        do {
            _ = try await container.accept(metadata)
            store = SyncStore()
            store.role = .member
            store.zoneOwnerName = metadata.share.recordID.zoneID.ownerName
            store.ownerDisplayName = Self.displayName(of: metadata.ownerIdentity)
            store.save()
            role = .member
            ownerName = store.ownerDisplayName
            makeEngine()
            try await engine?.fetchChanges()
            scanLocalChanges()
            try await engine?.sendChanges()
            status = .synced(.now)
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    // MARK: - Leave / stop

    /// Owner: stops sharing (co-parents lose access). Member: leaves the family.
    /// Data already on this iPhone stays.
    func leaveFamily() async {
        status = .working(role == .owner ? "Stopping sharing…" : "Leaving the family…")
        await removeRemoteShare(role: role, zoneID: zoneID)
        resetLocalState()
    }

    /// Used by Reset BrightTime: disconnect right away so erasing this iPhone
    /// never deletes the shared family from iCloud.
    func disconnectForReset() {
        let currentRole = role
        let currentZone = zoneID
        resetLocalState()
        guard currentRole != .none else { return }
        Task { await removeRemoteShare(role: currentRole, zoneID: currentZone) }
    }

    /// Gives children synced before this iPhone had a parent profile to that parent.
    func adoptOrphans() {
        guard let context, let parent = localParent() else { return }
        let orphans = ((try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []).filter { $0.parent == nil }
        guard !orphans.isEmpty else { return }
        for child in orphans { child.parent = parent }
        try? context.save()
    }

    // MARK: - Engine

    private var context: ModelContext? { modelContainer?.mainContext }

    private var container: CKContainer {
        if let cloudContainer { return cloudContainer }
        let created = CKContainer(identifier: Self.containerID)
        cloudContainer = created
        return created
    }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: Self.zoneName,
            ownerName: store.role == .member ? (store.zoneOwnerName ?? CKCurrentUserDefaultName) : CKCurrentUserDefaultName
        )
    }

    private func makeEngine() {
        let database = role == .member ? container.sharedCloudDatabase : container.privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: store.engineState,
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        // CKSyncEngine fetches automatically when iCloud pushes a change.
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func resetLocalState() {
        scanLoop?.cancel()
        scanLoop = nil
        engine = nil
        store = SyncStore()
        store.save()
        role = .none
        ownerName = nil
        participants = []
        status = .idle
    }

    private func requireAccount() async throws {
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else { throw CKError(.notAuthenticated) }
    }

    private func existingShare() async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await container.privateCloudDatabase.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
        _ = try result.saveResults[zone.zoneID]?.get()
    }

    private func fetchOrCreateShare() async throws -> CKShare {
        let existing = try await existingShare()
        if let existing { return existing }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "BrightTime family" as CKRecordValue
        share.publicPermission = .none
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if let saved = try result.saveResults[share.recordID]?.get() as? CKShare {
            return saved
        }
        return share
    }

    private func removeRemoteShare(role: Role, zoneID: CKRecordZone.ID) async {
        switch role {
        case .owner:
            _ = try? await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
        case .member:
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            if (try? await container.sharedCloudDatabase.deleteRecord(withID: shareID)) == nil {
                _ = try? await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
            }
        case .none:
            break
        }
    }

    private func presentSharingController(for share: CKShare) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = SharingControllerDelegate()
        sharingDelegate = delegate
        controller.delegate = delegate
        Self.topViewController()?.present(controller, animated: true)
    }

    fileprivate func sharingControllerFinished(stoppedSharing: Bool) {
        sharingDelegate = nil
        if stoppedSharing {
            Task { await leaveFamily() }
        } else {
            Task { await refreshParticipants() }
        }
    }

    // MARK: - Local changes → pending saves / deletes

    func scanLocalChanges() {
        guard let engine, let context else { return }
        var current: [String: String] = [:]

        for child in (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? [] {
            current[RecordKind.child.recordName(child.id)] = Fingerprint.of(child)
        }
        for device in (try? context.fetch(FetchDescriptor<Device>())) ?? [] {
            current[RecordKind.device.recordName(device.id)] = Fingerprint.of(device)
        }
        for session in (try? context.fetch(FetchDescriptor<UsageSession>())) ?? [] {
            current[RecordKind.session.recordName(session.id)] = Fingerprint.of(session)
        }
        for credit in (try? context.fetch(FetchDescriptor<TimeCredit>())) ?? [] {
            current[RecordKind.credit.recordName(credit.id)] = Fingerprint.of(credit)
        }
        for activity in (try? context.fetch(FetchDescriptor<EarnActivity>())) ?? [] {
            current[RecordKind.activity.recordName(activity.id)] = Fingerprint.of(activity)
        }
        for request in (try? context.fetch(FetchDescriptor<TimeRequest>())) ?? [] {
            current[RecordKind.request.recordName(request.id)] = Fingerprint.of(request)
        }
        for alert in (try? context.fetch(FetchDescriptor<PasscodeAlert>())) ?? [] {
            current[RecordKind.alert.recordName(alert.id)] = Fingerprint.of(alert)
        }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, fingerprint) in current where store.manifest[name] != fingerprint {
            changes.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: zoneID)))
            store.manifest[name] = fingerprint
        }
        for name in store.manifest.keys where current[name] == nil {
            changes.append(.deleteRecord(CKRecord.ID(recordName: name, zoneID: zoneID)))
            store.manifest[name] = nil
            store.systemFields[name] = nil
        }

        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        store.save()
    }

    // MARK: - Building records

    private func makeBatch(
        for pending: [CKSyncEngine.PendingRecordZoneChange],
        engine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {
        var records: [CKRecord] = []
        var deletions: [CKRecord.ID] = []
        var missing: [CKSyncEngine.PendingRecordZoneChange] = []

        for change in pending {
            guard records.count + deletions.count < batchLimit else { break }
            switch change {
            case .saveRecord(let recordID):
                if let record = record(for: recordID) {
                    records.append(record)
                } else {
                    missing.append(change)
                }
            case .deleteRecord(let recordID):
                deletions.append(recordID)
            @unknown default:
                break
            }
        }

        if !missing.isEmpty {
            engine.state.remove(pendingRecordZoneChanges: missing)
        }
        guard !records.isEmpty || !deletions.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, recordIDsToDelete: deletions, atomicByZone: false)
    }

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let parsed = RecordKind.parse(recordID.recordName), let context else { return nil }
        let (kind, id) = (parsed.kind, parsed.id)

        let record: CKRecord
        if let data = store.systemFields[recordID.recordName], let cached = Self.decodeSystemFields(data) {
            record = cached
        } else {
            record = CKRecord(recordType: kind.rawValue, recordID: recordID)
        }

        switch kind {
        case .child:
            guard let child = fetchOne(ChildProfile.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: child)
        case .device:
            guard let device = fetchOne(Device.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: device)
        case .session:
            guard let session = fetchOne(UsageSession.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: session)
        case .credit:
            guard let credit = fetchOne(TimeCredit.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: credit)
        case .activity:
            guard let activity = fetchOne(EarnActivity.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: activity)
        case .request:
            guard let request = fetchOne(TimeRequest.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: request)
        case .alert:
            guard let alert = fetchOne(PasscodeAlert.self, id: id, in: context) else { return nil }
            RecordMapper.fill(record, from: alert)
        }
        return record
    }

    // MARK: - Applying remote changes

    private func applyFetched(modifications: [CKRecord], deletions: [(CKRecord.ID, CKRecord.RecordType)]) {
        guard let context else { return }
        let ordered = (modifications + store.takeUnresolved()).sorted {
            (RecordKind(rawValue: $0.recordType)?.order ?? 9) < (RecordKind(rawValue: $1.recordType)?.order ?? 9)
        }

        var unresolved: [CKRecord] = []
        for record in ordered where record.recordID.zoneID.zoneName == Self.zoneName {
            if !apply(record, in: context) {
                unresolved.append(record)
            }
        }
        // A second pass picks up records whose child arrived later in this batch.
        unresolved = unresolved.filter { !apply($0, in: context) }
        store.keepUnresolved(unresolved)

        for (recordID, _) in deletions {
            delete(recordID, in: context)
        }
        try? context.save()
        store.save()

        let arrived = arrivedRequests
        arrivedRequests = []
        for request in arrived {
            AppNotifications.shared.requestArrivedFromSync(request, context: context)
        }
        let alerts = arrivedAlerts
        arrivedAlerts = []
        for alert in alerts {
            AppNotifications.shared.passcodeAlertArrivedFromSync(alert)
        }
    }

    /// Returns false when the record points at a child that isn't here yet.
    private func apply(_ record: CKRecord, in context: ModelContext) -> Bool {
        guard let parsed = RecordKind.parse(record.recordID.recordName) else { return true }
        let (kind, id) = (parsed.kind, parsed.id)
        let name = record.recordID.recordName

        switch kind {
        case .child:
            let child = fetchOne(ChildProfile.self, id: id, in: context) ?? {
                let created = ChildProfile(id: id, name: record.string("name") ?? "Kid", parent: localParent())
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: child)
            if child.parent == nil { child.parent = localParent() }
            store.manifest[name] = Fingerprint.of(child)

        case .device:
            var owner: ChildProfile?
            if let childID = record.uuid("childID") {
                guard let found = fetchOne(ChildProfile.self, id: childID, in: context) else { return false }
                owner = found
            }
            let device = fetchOne(Device.self, id: id, in: context) ?? {
                let created = Device(id: id, name: record.string("name") ?? "Device", kind: .other)
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: device)
            device.child = owner
            store.manifest[name] = Fingerprint.of(device)

        case .session:
            var owner: ChildProfile?
            if let childID = record.uuid("childID") {
                guard let found = fetchOne(ChildProfile.self, id: childID, in: context) else { return false }
                owner = found
            }
            var screen: Device?
            if let deviceID = record.uuid("deviceID") {
                guard let found = fetchOne(Device.self, id: deviceID, in: context) else { return false }
                screen = found
            }
            let session = fetchOne(UsageSession.self, id: id, in: context) ?? {
                let created = UsageSession(id: id, startedAt: record.date("startedAt") ?? .now, endedAt: record.date("endedAt") ?? .now)
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: session)
            session.child = owner
            session.device = screen
            store.manifest[name] = Fingerprint.of(session)

        case .credit:
            guard let childID = record.uuid("childID"),
                  let owner = fetchOne(ChildProfile.self, id: childID, in: context) else { return false }
            let credit = fetchOne(TimeCredit.self, id: id, in: context) ?? {
                let created = TimeCredit(id: id, kind: .earned, minutes: 0, title: "", symbol: "star.fill")
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: credit)
            credit.child = owner
            store.manifest[name] = Fingerprint.of(credit)

        case .activity:
            let activity = fetchOne(EarnActivity.self, id: id, in: context) ?? {
                let created = EarnActivity(id: id, name: "", symbol: "star.fill", minutes: 15)
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: activity)
            store.manifest[name] = Fingerprint.of(activity)

        case .request:
            let existing = fetchOne(TimeRequest.self, id: id, in: context)
            let previousStatus = existing?.status
            let request = existing ?? {
                let created = TimeRequest(id: id, childID: record.uuid("childID") ?? UUID(), minutes: 15)
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: request)
            store.manifest[name] = Fingerprint.of(request)
            if previousStatus != request.status {
                arrivedRequests.append(request)
            }

        case .alert:
            let existing = fetchOne(PasscodeAlert.self, id: id, in: context)
            let previousAttempts = existing?.attempts ?? 0
            let alert = existing ?? {
                let created = PasscodeAlert(attempts: 0, deviceLabel: "", deviceID: "")
                context.insert(created)
                return created
            }()
            RecordMapper.apply(record, to: alert)
            store.manifest[name] = Fingerprint.of(alert)
            if alert.attempts > previousAttempts, !alert.acknowledged {
                arrivedAlerts.append(alert)
            }
        }

        store.systemFields[name] = Self.encodeSystemFields(record)
        return true
    }

    private func delete(_ recordID: CKRecord.ID, in context: ModelContext) {
        let name = recordID.recordName
        store.manifest[name] = nil
        store.systemFields[name] = nil
        guard let parsed = RecordKind.parse(name) else { return }
        let id = parsed.id
        switch parsed.kind {
        case .child:
            if let model = fetchOne(ChildProfile.self, id: id, in: context) { context.delete(model) }
        case .device:
            if let model = fetchOne(Device.self, id: id, in: context) { context.delete(model) }
        case .session:
            if let model = fetchOne(UsageSession.self, id: id, in: context) { context.delete(model) }
        case .credit:
            if let model = fetchOne(TimeCredit.self, id: id, in: context) { context.delete(model) }
        case .activity:
            if let model = fetchOne(EarnActivity.self, id: id, in: context) { context.delete(model) }
        case .request:
            if let model = fetchOne(TimeRequest.self, id: id, in: context) { context.delete(model) }
        case .alert:
            if let model = fetchOne(PasscodeAlert.self, id: id, in: context) { context.delete(model) }
        }
    }

    private func localParent() -> ParentProfile? {
        try? context?.fetch(FetchDescriptor<ParentProfile>(sortBy: [SortDescriptor(\.createdAt)])).first
    }

    private func fetchOne<Model: PersistentModel & SyncIdentifiable>(
        _ type: Model.Type,
        id: UUID,
        in context: ModelContext
    ) -> Model? {
        ((try? context.fetch(FetchDescriptor<Model>(predicate: Model.matching(id)))) ?? []).first
    }

    // MARK: - Engine events

    fileprivate func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            store.engineState = update.stateSerialization
            store.save()

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                break
            case .signOut, .switchAccounts:
                resetLocalState()
                status = .failed("iCloud account changed, so family sharing was turned off on this iPhone.")
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID.zoneName == Self.zoneName }) {
                resetLocalState()
                status = .failed("The family share ended. Everything synced so far stays on this iPhone.")
            }

        case .fetchedRecordZoneChanges(let changes):
            applyFetched(
                modifications: changes.modifications.map(\.record),
                deletions: changes.deletions.map { ($0.recordID, $0.recordType) }
            )

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                syncLog.error("Zone save failed: \(String(describing: failure.error), privacy: .public)")
                status = .failed(Self.message(for: failure.error))
            }

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords {
                store.systemFields[saved.recordID.recordName] = Self.encodeSystemFields(saved)
            }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var needsZone = false
            var otherFailures: [CKError] = []
            for failure in sent.failedRecordSaves {
                let recordID = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    if let server = failure.error.serverRecord {
                        store.systemFields[recordID.recordName] = Self.encodeSystemFields(server)
                    }
                    retry.append(.saveRecord(recordID))
                case .unknownItem:
                    store.systemFields[recordID.recordName] = nil
                    retry.append(.saveRecord(recordID))
                case .zoneNotFound, .userDeletedZone:
                    if role == .owner {
                        needsZone = true
                        retry.append(.saveRecord(recordID))
                    } else {
                        resetLocalState()
                        status = .failed("The family share ended. Everything synced so far stays on this iPhone.")
                        return
                    }
                case .permissionFailure:
                    status = .failed("You can view this family but can't make changes. Ask the parent who invited you to give you edit access.")
                case .limitExceeded:
                    batchLimit = max(batchLimit / 2, 5)
                    retry.append(.saveRecord(recordID))
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .requestRateLimited, .notAuthenticated, .operationCancelled, .batchRequestFailed:
                    // CKSyncEngine retries these on its own.
                    break
                default:
                    otherFailures.append(failure.error)
                }
            }
            for failure in sent.failedRecordSaves {
                syncLog.error("Save failed for \(failure.record.recordID.recordName, privacy: .public): \(String(describing: failure.error), privacy: .public)")
            }
            if let first = otherFailures.first {
                uploadRoundFailed = true
                let count = otherFailures.count
                status = .failed("Couldn't upload \(count) item\(count == 1 ? "" : "s") to iCloud. \(Self.detail(first))")
            }
            if needsZone {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            }
            if !retry.isEmpty {
                engine.state.add(pendingRecordZoneChanges: retry)
            }
            store.save()

        case .willSendChanges:
            uploadRoundFailed = false

        case .didFetchChanges:
            if case .working = status {} else if case .failed = status {} else { status = .synced(.now) }

        case .didSendChanges:
            if case .working = status {} else if !uploadRoundFailed { status = .synced(.now) }

        default:
            break
        }
    }

    // MARK: - Helpers

    static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated:
            return "Sign in to iCloud in the Settings app to share BrightTime with a co-parent."
        case .networkUnavailable, .networkFailure:
            return "You're offline. Try again when you're connected."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .participantMayNeedVerification:
            return "Open the invite link from the Messages or Mail app on this iPhone."
        case .badContainer, .missingEntitlement:
            return "iCloud isn't set up for this build of BrightTime yet."
        default:
            return "Couldn't sync with iCloud. \(detail(error))"
        }
    }

    /// The error with its CloudKit code and the first underlying reason, so a
    /// screenshot of the message is enough to tell what went wrong.
    static func detail(_ error: CKError) -> String {
        var parts = ["\(error.localizedDescription) (code \(error.code.rawValue))"]
        if let partial = error.partialErrorsByItemID?.values.first as? CKError {
            parts.append("\(partial.localizedDescription) (code \(partial.code.rawValue))")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append(underlying.localizedDescription)
        }
        return parts.joined(separator: " · ")
    }

    private static func displayName(of identity: CKUserIdentity) -> String? {
        if let components = identity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber
    }

    private static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - CKSyncEngineDelegate

extension FamilySync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, engine: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await makeBatch(for: pending, engine: syncEngine)
    }
}

// MARK: - Sharing sheet delegate

private final class SharingControllerDelegate: NSObject, UICloudSharingControllerDelegate {
    func itemTitle(for csc: UICloudSharingController) -> String? {
        "BrightTime family"
    }

    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        UIImage(systemName: "sun.max.fill")?.pngData()
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        FamilySync.shared.sharingControllerFinished(stoppedSharing: false)
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        FamilySync.shared.sharingControllerFinished(stoppedSharing: false)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        FamilySync.shared.sharingControllerFinished(stoppedSharing: true)
    }
}

// MARK: - Accepting invites (scene delegate)

final class BrightTimeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = BrightTimeSceneDelegate.self
        return configuration
    }
}

final class BrightTimeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { await FamilySync.shared.accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await FamilySync.shared.accept(cloudKitShareMetadata) }
    }
}

// MARK: - Persisted sync state

private struct SyncStore: Codable {
    var role: FamilySync.Role = .none
    var zoneOwnerName: String?
    var ownerDisplayName: String?
    var engineState: CKSyncEngine.State.Serialization?
    /// recordName → fingerprint of what was last synced.
    var manifest: [String: String] = [:]
    /// recordName → archived CKRecord system fields (change tag), so saves don't conflict.
    var systemFields: [String: Data] = [:]
    /// Records that arrived before the child they belong to.
    var unresolved: [Data] = []

    private static var url: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "BrightTimeFamilySync.json")
    }

    static func load() -> SyncStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(SyncStore.self, from: data) else { return SyncStore() }
        return store
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }

    mutating func takeUnresolved() -> [CKRecord] {
        let records = unresolved.compactMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: $0)
        }
        unresolved = []
        return records
    }

    mutating func keepUnresolved(_ records: [CKRecord]) {
        unresolved = records.compactMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
    }
}

// MARK: - Record mapping

private enum RecordKind: String, CaseIterable {
    case child = "Child"
    case device = "Device"
    case session = "Session"
    case credit = "Credit"
    case activity = "Activity"
    case request = "Request"
    case alert = "PasscodeAlert"

    /// Parents before the things that point at them.
    var order: Int {
        switch self {
        case .activity: 0
        case .child: 1
        case .device: 2
        case .credit: 3
        case .session: 4
        case .request: 5
        case .alert: 6
        }
    }

    func recordName(_ id: UUID) -> String {
        "\(rawValue).\(id.uuidString)"
    }

    static func parse(_ recordName: String) -> (kind: RecordKind, id: UUID)? {
        let parts = recordName.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = RecordKind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        return (kind: kind, id: id)
    }
}

private protocol SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<Self>
}

extension ChildProfile: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<ChildProfile> { #Predicate { $0.id == id } }
}

extension Device: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<Device> { #Predicate { $0.id == id } }
}

extension UsageSession: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<UsageSession> { #Predicate { $0.id == id } }
}

extension TimeCredit: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<TimeCredit> { #Predicate { $0.id == id } }
}

extension EarnActivity: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<EarnActivity> { #Predicate { $0.id == id } }
}

extension TimeRequest: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<TimeRequest> { #Predicate { $0.id == id } }
}

extension PasscodeAlert: SyncIdentifiable {
    static func matching(_ id: UUID) -> Predicate<PasscodeAlert> { #Predicate { $0.id == id } }
}

@MainActor
private enum RecordMapper {
    static func fill(_ record: CKRecord, from child: ChildProfile) {
        record["name"] = child.name
        record["dailyLimitMinutes"] = child.dailyLimitMinutes
        record["weekdayLimitMinutes"] = child.weekdayLimitMinutes
        record["weekendLimitMinutes"] = child.weekendLimitMinutes
        record["gender"] = child.genderRawValue
        record["avatar"] = child.defaultAvatarRawValue
        record["color"] = child.colorRawValue
        // As a file (CKAsset), not a field: fields are capped at 1 MB per record.
        record["photo"] = nil
        record["photoAsset"] = PhotoAssets.asset(for: child.profilePhotoData, name: child.id.uuidString)
        record["isActive"] = child.isActive
        record["createdAt"] = child.createdAt
        record["updatedAt"] = child.updatedAt
    }

    static func apply(_ record: CKRecord, to child: ChildProfile) {
        child.name = record.string("name") ?? child.name
        child.dailyLimitMinutes = record.int("dailyLimitMinutes") ?? child.dailyLimitMinutes
        child.weekdayLimitMinutes = record.int("weekdayLimitMinutes")
        child.weekendLimitMinutes = record.int("weekendLimitMinutes")
        child.genderRawValue = record.string("gender")
        child.defaultAvatarRawValue = record.string("avatar")
        child.colorRawValue = record.string("color")
        if let asset = record["photoAsset"] as? CKAsset, let url = asset.fileURL {
            child.profilePhotoData = try? Data(contentsOf: url)
        } else {
            child.profilePhotoData = record["photo"] as? Data
        }
        child.isActive = record.bool("isActive") ?? child.isActive
        child.createdAt = record.date("createdAt") ?? child.createdAt
        child.updatedAt = record.date("updatedAt") ?? child.updatedAt
    }

    static func fill(_ record: CKRecord, from device: Device) {
        record["name"] = device.name
        record["kind"] = device.kindRawValue
        record["isShared"] = device.isShared
        record["isActive"] = device.isActive
        record["childID"] = device.child?.id.uuidString
        record["createdAt"] = device.createdAt
        record["updatedAt"] = device.updatedAt
    }

    static func apply(_ record: CKRecord, to device: Device) {
        device.name = record.string("name") ?? device.name
        device.kindRawValue = record.string("kind") ?? device.kindRawValue
        device.isShared = record.bool("isShared") ?? device.isShared
        device.isActive = record.bool("isActive") ?? device.isActive
        device.createdAt = record.date("createdAt") ?? device.createdAt
        device.updatedAt = record.date("updatedAt") ?? device.updatedAt
    }

    static func fill(_ record: CKRecord, from session: UsageSession) {
        record["startedAt"] = session.startedAt
        record["endedAt"] = session.endedAt
        record["note"] = session.note
        record["childID"] = session.child?.id.uuidString
        record["deviceID"] = session.device?.id.uuidString
        record["createdAt"] = session.createdAt
        record["updatedAt"] = session.updatedAt
    }

    static func apply(_ record: CKRecord, to session: UsageSession) {
        session.startedAt = record.date("startedAt") ?? session.startedAt
        session.endedAt = record.date("endedAt") ?? session.endedAt
        session.note = record.string("note")
        session.createdAt = record.date("createdAt") ?? session.createdAt
        session.updatedAt = record.date("updatedAt") ?? session.updatedAt
    }

    static func fill(_ record: CKRecord, from credit: TimeCredit) {
        record["kind"] = credit.kindRawValue
        record["minutes"] = credit.minutes
        record["title"] = credit.title
        record["symbol"] = credit.symbol
        record["day"] = credit.day
        record["childID"] = credit.child?.id.uuidString
        record["createdAt"] = credit.createdAt
        record["updatedAt"] = credit.updatedAt
    }

    static func apply(_ record: CKRecord, to credit: TimeCredit) {
        credit.kindRawValue = record.string("kind") ?? credit.kindRawValue
        credit.minutes = record.int("minutes") ?? credit.minutes
        credit.title = record.string("title") ?? credit.title
        credit.symbol = record.string("symbol") ?? credit.symbol
        credit.day = record.date("day") ?? credit.day
        credit.createdAt = record.date("createdAt") ?? credit.createdAt
        credit.updatedAt = record.date("updatedAt") ?? credit.updatedAt
    }

    static func fill(_ record: CKRecord, from activity: EarnActivity) {
        record["name"] = activity.name
        record["symbol"] = activity.symbol
        record["minutes"] = activity.minutes
        record["sortOrder"] = activity.sortOrder
        record["isActive"] = activity.isActive
        record["createdAt"] = activity.createdAt
        record["updatedAt"] = activity.updatedAt
    }

    static func fill(_ record: CKRecord, from request: TimeRequest) {
        record["childID"] = request.childID.uuidString
        record["minutes"] = request.minutes
        record["status"] = request.statusRawValue
        record["day"] = request.day
        record["createdAt"] = request.createdAt
        record["decidedAt"] = request.decidedAt
        record["updatedAt"] = request.updatedAt
    }

    static func apply(_ record: CKRecord, to request: TimeRequest) {
        request.childID = record.uuid("childID") ?? request.childID
        request.minutes = record.int("minutes") ?? request.minutes
        request.statusRawValue = record.string("status") ?? request.statusRawValue
        request.day = record.date("day") ?? request.day
        request.createdAt = record.date("createdAt") ?? request.createdAt
        request.decidedAt = record.date("decidedAt")
        request.updatedAt = record.date("updatedAt") ?? request.updatedAt
    }

    static func fill(_ record: CKRecord, from alert: PasscodeAlert) {
        record["attempts"] = alert.attempts
        record["firstAt"] = alert.firstAt
        record["lastAt"] = alert.lastAt
        record["deviceLabel"] = alert.deviceLabel
        record["deviceID"] = alert.deviceID
        record["acknowledged"] = alert.acknowledged
        record["updatedAt"] = alert.updatedAt
    }

    static func apply(_ record: CKRecord, to alert: PasscodeAlert) {
        alert.attempts = record.int("attempts") ?? alert.attempts
        alert.firstAt = record.date("firstAt") ?? alert.firstAt
        alert.lastAt = record.date("lastAt") ?? alert.lastAt
        alert.deviceLabel = record.string("deviceLabel") ?? alert.deviceLabel
        alert.deviceID = record.string("deviceID") ?? alert.deviceID
        alert.acknowledged = record.bool("acknowledged") ?? alert.acknowledged
        alert.updatedAt = record.date("updatedAt") ?? alert.updatedAt
    }

    static func apply(_ record: CKRecord, to activity: EarnActivity) {
        activity.name = record.string("name") ?? activity.name
        activity.symbol = record.string("symbol") ?? activity.symbol
        activity.minutes = record.int("minutes") ?? activity.minutes
        activity.sortOrder = record.int("sortOrder") ?? activity.sortOrder
        activity.isActive = record.bool("isActive") ?? activity.isActive
        activity.createdAt = record.date("createdAt") ?? activity.createdAt
        activity.updatedAt = record.date("updatedAt") ?? activity.updatedAt
    }
}

/// A cheap, stable summary of a record's synced fields.
@MainActor
private enum Fingerprint {
    static func of(_ child: ChildProfile) -> String {
        [
            child.name, "\(child.dailyLimitMinutes)", "\(child.weekdayLimitMinutes ?? -1)",
            "\(child.weekendLimitMinutes ?? -1)", child.genderRawValue ?? "", child.defaultAvatarRawValue ?? "",
            child.colorRawValue ?? "", hash(child.profilePhotoData), "\(child.isActive)", stamp(child.createdAt),
            stamp(child.updatedAt),
        ].joined(separator: "|")
    }

    static func of(_ device: Device) -> String {
        [
            device.name, device.kindRawValue, "\(device.isShared)", "\(device.isActive)",
            device.child?.id.uuidString ?? "", stamp(device.createdAt), stamp(device.updatedAt),
        ].joined(separator: "|")
    }

    static func of(_ session: UsageSession) -> String {
        [
            stamp(session.startedAt), stamp(session.endedAt), session.note ?? "",
            session.child?.id.uuidString ?? "", session.device?.id.uuidString ?? "",
            stamp(session.createdAt), stamp(session.updatedAt),
        ].joined(separator: "|")
    }

    static func of(_ credit: TimeCredit) -> String {
        [
            credit.kindRawValue, "\(credit.minutes)", credit.title, credit.symbol, stamp(credit.day),
            credit.child?.id.uuidString ?? "", stamp(credit.createdAt), stamp(credit.updatedAt),
        ].joined(separator: "|")
    }

    static func of(_ activity: EarnActivity) -> String {
        [
            activity.name, activity.symbol, "\(activity.minutes)", "\(activity.sortOrder)",
            "\(activity.isActive)", stamp(activity.createdAt), stamp(activity.updatedAt),
        ].joined(separator: "|")
    }

    static func of(_ request: TimeRequest) -> String {
        [
            request.childID.uuidString, "\(request.minutes)", request.statusRawValue, stamp(request.day),
            stamp(request.createdAt), request.decidedAt.map(stamp) ?? "", stamp(request.updatedAt),
        ].joined(separator: "|")
    }

    static func of(_ alert: PasscodeAlert) -> String {
        [
            "\(alert.attempts)", stamp(alert.firstAt), stamp(alert.lastAt), alert.deviceLabel,
            alert.deviceID, "\(alert.acknowledged)", stamp(alert.updatedAt),
        ].joined(separator: "|")
    }

    /// Millisecond precision, matching what CloudKit stores.
    private static func stamp(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
    }

    /// FNV-1a over the bytes (Swift's `hashValue` changes every launch).
    private static func hash(_ data: Data?) -> String {
        guard let data else { return "" }
        var value: UInt64 = 0xcbf29ce484222325
        for byte in data {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
        return String(value, radix: 16)
    }
}

/// Temporary files for photos uploaded as CKAssets.
private enum PhotoAssets {
    static func asset(for data: Data?, name: String) -> CKAsset? {
        guard let data else { return nil }
        let folder = URL.cachesDirectory.appending(path: "BrightTimeSyncPhotos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return CKAsset(fileURL: url)
        } catch {
            return nil
        }
    }
}

private extension CKRecord {
    func string(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func bool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
    func date(_ key: String) -> Date? { self[key] as? Date }
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
}
