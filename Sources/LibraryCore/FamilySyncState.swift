import Foundation

public enum FamilyRole: String, Codable, Sendable { case owner, writer, reader, revoked }

/// Snapshot plus outbox. Both are persisted in one SQLite transaction.
public struct FamilySyncState: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let replicaID: UUID
    public let accountID: String
    public let zoneName: String
    public let zoneOwner: String
    public let recordName: String
    public let isOwner: Bool
    public var role: FamilyRole
    public var isCreating: Bool
    public var envelope: FamilyEnvelope
    public private(set) var generation: UInt64 = 0
    public var acknowledgedGeneration: UInt64 = 0
    public var lastSync: Date?

    public init(accountID: String, zoneName: String, zoneOwner: String, recordName: String,
                isOwner: Bool, envelope: FamilyEnvelope, role: FamilyRole? = nil, isCreating: Bool = false) {
        self.sessionID = UUID(); self.replicaID = UUID()
        self.accountID = accountID; self.zoneName = zoneName; self.zoneOwner = zoneOwner
        self.recordName = recordName; self.isOwner = isOwner; self.envelope = envelope
        self.role = role ?? (isOwner ? .owner : .writer)
        self.isCreating = isCreating
    }

    public var canEdit: Bool { role == .owner || role == .writer }
    public var hasPendingChanges: Bool { generation > acknowledgedGeneration }

    /// Keep both the owner's unsent work and the last participant changes after
    /// CloudKit has confirmed that the root is no longer shared.
    public func snapshotAfterStoppingSharing(finalEnvelope: FamilyEnvelope) throws -> LibrarySnapshot {
        guard isOwner, !isCreating else { throw FamilyError.readOnly }
        return try envelope.merged(with: finalEnvelope).snapshot()
    }

    public mutating func edit(_ snapshot: LibrarySnapshot, date: Date = Date()) throws {
        guard canEdit else { throw FamilyError.readOnly }
        guard generation < UInt64.max else { throw FamilyError.invalidData }
        let updated = try envelope.applying(snapshot, replicaID: replicaID, counter: generation + 1, date: date)
        guard updated != envelope else { return }
        envelope = updated
        generation += 1
    }
    public func validate() throws {
        guard !accountID.isEmpty, !zoneName.isEmpty, !zoneOwner.isEmpty, !recordName.isEmpty,
              acknowledgedGeneration <= generation else { throw FamilyError.invalidData }
        _ = try envelope.snapshot()
    }
}

public struct FamilyRemote: Sendable {
    public var envelope: FamilyEnvelope
    public var changeTag: String
    public var role: FamilyRole
    public init(envelope: FamilyEnvelope, changeTag: String, role: FamilyRole) {
        self.envelope = envelope; self.changeTag = changeTag; self.role = role
    }
}

@MainActor public protocol FamilyTransport: AnyObject {
    func accountID() async throws -> String
    func fetch(_ state: FamilySyncState) async throws -> FamilyRemote
    func save(_ envelope: FamilyEnvelope, state: FamilySyncState, changeTag: String) async throws -> FamilyRemote
}
