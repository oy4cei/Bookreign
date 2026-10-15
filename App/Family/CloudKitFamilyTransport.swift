import CloudKit
import LibraryCore
import Foundation

@MainActor
final class CloudKitFamilyTransport: FamilyTransport {
    static let containerIdentifier = "iCloud.com.bookslibrary.polka"
    lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var records: [CKRecord.ID: CKRecord] = [:]

    func accountID() async throws -> String {
        switch try await container.accountStatus() {
        case .available: break
        case .noAccount, .restricted: throw FamilyError.accountChanged
        default: throw FamilyError.unavailable
        }
        return try await container.userRecordID().recordName
    }

    func database(_ state: FamilySyncState) -> CKDatabase {
        state.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }
    func recordID(_ state: FamilySyncState) -> CKRecord.ID {
        CKRecord.ID(recordName: state.recordName, zoneID: CKRecordZone.ID(zoneName: state.zoneName, ownerName: state.zoneOwner))
    }

    func fetch(_ state: FamilySyncState) async throws -> FamilyRemote {
        do {
            try await verifyAccount(state)
            let record = try await database(state).record(for: recordID(state))
            let share = try await share(for: record, state: state)
            let role = try membership(share, state: state)
            let envelope = try decode(record)
            guard envelope.libraryID == state.envelope.libraryID else { throw FamilyError.wrongLibrary }
            try await verifyAccount(state)
            records[record.recordID] = record
            return FamilyRemote(envelope: envelope, changeTag: record.recordChangeTag ?? "", role: role)
        } catch { throw mapped(error) }
    }

    func save(_ envelope: FamilyEnvelope, state: FamilySyncState, changeTag: String) async throws -> FamilyRemote {
        guard state.canEdit else { throw FamilyError.readOnly }
        guard let record = records[recordID(state)], record.recordChangeTag == changeTag else { throw FamilyError.conflict }
        let file = try stagingFile(envelope)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try await verifyAccount(state)
            let share = try await share(for: record, state: state)
            let role = try membership(share, state: state)
            guard role == .owner || role == .writer else { throw FamilyError.readOnly }
            record["payload"] = CKAsset(fileURL: file)
            record["formatVersion"] = 1 as NSNumber
            try await verifyAccount(state)
            let result = try await database(state).modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            let saved = try result.saveResults[record.recordID]!.get()
            try await verifyAccount(state)
            records[saved.recordID] = saved
            return FamilyRemote(envelope: envelope, changeTag: saved.recordChangeTag ?? "", role: role)
        } catch {
            records.removeValue(forKey: record.recordID)
            if let cloud = error as? CKError, cloud.code == .permissionFailure {
                // A writer may have become a reader while the write was in flight.
                // Only a failed read/membership check establishes revocation.
                let current = try await fetch(state)
                if current.role == .reader { throw FamilyError.readOnly }
                throw FamilyError.unavailable
            }
            throw mapped(error)
        }
    }

    /// Retry reuses the persisted zone/root IDs; a lost response never creates a second library.
    func create(_ state: FamilySyncState) async throws -> (FamilyRemote, CKShare) {
        try await verifyAccount(state)
        let id = recordID(state)
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: id.zoneID))
        do {
            let existing = try await container.privateCloudDatabase.record(for: id)
            let share = try await share(for: existing, state: state)
            let envelope = try decode(existing)
            guard envelope.libraryID == state.envelope.libraryID else { throw FamilyError.wrongLibrary }
            try await verifyAccount(state)
            records[id] = existing
            return (FamilyRemote(envelope: envelope, changeTag: existing.recordChangeTag ?? "", role: .owner), share)
        } catch let error as CKError where error.code == .unknownItem {
            // Only an absent record permits creation. Any other error leaves local data untouched.
        }
        let record = CKRecord(recordType: "FamilyLibrarySnapshot", recordID: id)
        let shareID = CKRecord.ID(recordName: "share-" + state.envelope.libraryID.uuidString, zoneID: id.zoneID)
        let share = CKShare(rootRecord: record, shareID: shareID)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "Bookreign" as NSString
        let file = try stagingFile(state.envelope)
        defer { try? FileManager.default.removeItem(at: file) }
        record["payload"] = CKAsset(fileURL: file)
        record["formatVersion"] = 1 as NSNumber
        try await verifyAccount(state)
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [record, share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        let saved = try result.saveResults[id]!.get()
        guard let savedShare = try result.saveResults[shareID]!.get() as? CKShare else { throw FamilyError.invalidData }
        try await verifyAccount(state)
        records[id] = saved
        return (FamilyRemote(envelope: state.envelope, changeTag: saved.recordChangeTag ?? "", role: .owner), savedShare)
    }

    func accept(_ metadata: CKShare.Metadata) async throws -> FamilySyncState {
        guard metadata.containerIdentifier == Self.containerIdentifier,
              let rootID = metadata.hierarchicalRootRecordID else { throw FamilyError.wrongLibrary }
        let account = try await accountID()
        _ = try await container.accept(metadata)
        let record = try await container.sharedCloudDatabase.record(for: rootID)
        let envelope = try decode(record)
        var state = FamilySyncState(accountID: account, zoneName: rootID.zoneID.zoneName,
                                    zoneOwner: rootID.zoneID.ownerName, recordName: rootID.recordName,
                                    isOwner: false, envelope: envelope, role: .reader)
        let share = try await share(for: record, state: state)
        state.role = try membership(share, state: state)
        try await verifyAccount(state)
        records[rootID] = record
        return state
    }

    func sharingRecord(_ state: FamilySyncState) async throws -> CKShare {
        try await verifyAccount(state)
        let record = try await database(state).record(for: recordID(state))
        let share = try await share(for: record, state: state)
        _ = try membership(share, state: state)
        try await verifyAccount(state)
        return share
    }

    func finalOwnerEnvelope(_ state: FamilySyncState) async throws -> FamilyEnvelope {
        guard state.isOwner, !state.isCreating else { throw FamilyError.readOnly }
        try await verifyAccount(state)
        let record = try await container.privateCloudDatabase.record(for: recordID(state))
        // Do not detach while participants can still change the root. A failed
        // final download leaves the original local state/outbox available to retry.
        guard record.share == nil else { throw FamilyError.unavailable }
        let envelope = try decode(record)
        guard envelope.libraryID == state.envelope.libraryID else { throw FamilyError.wrongLibrary }
        try await verifyAccount(state)
        return envelope
    }

    func subscribe(_ state: FamilySyncState) async throws {
        try await verifyAccount(state)
        let subscription = CKDatabaseSubscription(subscriptionID: state.isOwner ? "bookreign-private-v1" : "bookreign-shared-v1")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database(state).save(subscription)
    }

    func reset() { records.removeAll() }

    func cancelCreation(_ state: FamilySyncState) async throws {
        guard state.isCreating, state.isOwner else { throw FamilyError.readOnly }
        try await verifyAccount(state)
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: recordID(state).zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // No server copy was created; local cancellation is still safe.
        }
        try await verifyAccount(state)
    }

    private func verifyAccount(_ state: FamilySyncState) async throws {
        try Task.checkCancellation()
        guard try await accountID() == state.accountID else { throw FamilyError.accountChanged }
        try Task.checkCancellation()
    }
    private func share(for record: CKRecord, state: FamilySyncState) async throws -> CKShare {
        guard let reference = record.share else {
            throw state.isOwner && !state.isCreating ? FamilyError.ownerStoppedSharing : FamilyError.revoked
        }
        guard let share = try await database(state).record(for: reference.recordID) as? CKShare else { throw FamilyError.invalidData }
        guard share.publicPermission == .none else { throw FamilyError.invalidData }
        return share
    }
    private func membership(_ share: CKShare, state: FamilySyncState) throws -> FamilyRole {
        guard let participant = share.currentUserParticipant else { throw FamilyError.revoked }
        if participant.role == .owner { return .owner }
        guard participant.acceptanceStatus == .accepted else { throw FamilyError.revoked }
        switch participant.permission {
        case .readWrite: return .writer
        case .readOnly: return .reader
        default: throw FamilyError.revoked
        }
    }
    private func decode(_ record: CKRecord) throws -> FamilyEnvelope {
        guard record.recordType == "FamilyLibrarySnapshot", (record["formatVersion"] as? NSNumber)?.intValue == 1,
              let asset = record["payload"] as? CKAsset, let file = asset.fileURL else { throw FamilyError.unsupportedVersion }
        // Read the CloudKit staging file while the fetched record is alive.
        return try FamilyAssetCodec.decode(FamilyAssetCodec.read(file))
    }
    private func stagingFile(_ envelope: FamilyEnvelope) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .posixPermissions: 0o700])
        let url = folder.appendingPathComponent(UUID().uuidString + ".brf")
        try FamilyAssetCodec.encode(envelope).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    private func mapped(_ error: Error) -> Error {
        guard let cloud = error as? CKError else { return error }
        switch cloud.code {
        case .serverRecordChanged: return FamilyError.conflict
        case .unknownItem, .zoneNotFound, .userDeletedZone, .permissionFailure: return FamilyError.revoked
        case .notAuthenticated: return FamilyError.accountChanged
        default: return error
        }
    }
}
