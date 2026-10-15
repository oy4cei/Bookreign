import Foundation

/// A durable import intent. Retries reuse timestamps even if the previous server write succeeded.
public struct PendingFamilyJoin: Codable, Equatable, Sendable {
    public let accountID: String
    public let zoneName: String
    public let zoneOwner: String
    public let recordName: String
    public let replicaID: UUID
    public private(set) var imported: FamilyEnvelope
    private var counter: UInt64 = 0
    private var replacements: [UUID: UUID] = [:]

    public init(snapshot: LibrarySnapshot, destination: FamilySyncState, date: Date = Date()) throws {
        accountID = destination.accountID; zoneName = destination.zoneName
        zoneOwner = destination.zoneOwner; recordName = destination.recordName
        replicaID = UUID()
        imported = try FamilyEnvelope(snapshot: snapshot, libraryID: destination.envelope.libraryID, replicaID: replicaID, date: date)
    }

    public func matches(_ destination: FamilySyncState) -> Bool {
        accountID == destination.accountID && zoneName == destination.zoneName && zoneOwner == destination.zoneOwner
            && recordName == destination.recordName && imported.libraryID == destination.envelope.libraryID
    }

    public mutating func updateLocal(_ snapshot: LibrarySnapshot, date: Date = Date()) throws {
        guard counter < UInt64.max else { throw FamilyError.invalidData }
        try snapshot.validate()
        // Local undo/backup restore may revive an ID already deleted by a previous
        // import attempt. Keep the cloud tombstone and import the restored entity
        // under a fresh, durable ID; every dependent reference follows that mapping.
        var mapping = replacements
        let deleted = imported.deletedEntityIDs
        let ids = snapshot.editions.map(\.id) + snapshot.copies.map(\.id)
            + snapshot.locations.map(\.id) + snapshot.loans.map(\.id)
        for id in ids where deleted.contains(mapping[id] ?? id) { mapping[id] = UUID() }
        func mapped(_ id: UUID) -> UUID { mapping[id] ?? id }
        var next = snapshot
        for i in next.editions.indices { next.editions[i].id = mapped(next.editions[i].id) }
        for i in next.locations.indices { next.locations[i].id = mapped(next.locations[i].id) }
        for i in next.copies.indices {
            next.copies[i].id = mapped(next.copies[i].id)
            next.copies[i].editionID = mapped(next.copies[i].editionID)
            next.copies[i].locationID = mapped(next.copies[i].locationID)
        }
        for i in next.loans.indices {
            next.loans[i].id = mapped(next.loans[i].id)
            next.loans[i].copyID = mapped(next.loans[i].copyID)
        }
        imported = try imported.applying(next, replicaID: replicaID, counter: counter + 1, date: date)
        replacements = mapping
        counter += 1
    }

    public func validate() throws {
        guard !accountID.isEmpty, !zoneName.isEmpty, !zoneOwner.isEmpty, !recordName.isEmpty else { throw FamilyError.invalidData }
        _ = try imported.snapshot()
    }
}
