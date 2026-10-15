import Foundation

public enum FamilyError: Error, Equatable, Sendable {
    case invalidData, unsupportedVersion, tooLarge, wrongLibrary, readOnly, accountChanged, revoked, ownerStoppedSharing, conflict, unavailable
}

public struct FamilyStamp: Codable, Equatable, Comparable, Sendable {
    public let date: Date
    public let replicaID: UUID
    public let counter: UInt64

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.replicaID != rhs.replicaID { return lhs.replicaID.uuidString < rhs.replicaID.uuidString }
        return lhs.counter < rhs.counter
    }
}

/// The wire values match the domain's JSON fields. No executable polymorphic decoding.
enum FamilyValue: Codable, Equatable, Sendable {
    case null, string(String), number(Double), strings([String])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let n = try? c.decode(Double.self), n.isFinite { self = .number(n) }
        else { self = .strings(try c.decode([String].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .strings(let a): try c.encode(a)
        }
    }
}

public struct FamilyEnvelope: Codable, Equatable, Sendable {
    struct Field: Codable, Equatable, Sendable {
        var value: FamilyValue
        var stamp: FamilyStamp
    }
    enum Kind: String, Codable, CaseIterable, Sendable {
        case edition, copy, location, loan
        var keys: Set<String> {
            switch self {
            case .edition: ["title", "author", "isbn", "language", "publisher", "year", "coverURL", "coverData", "notes", "genres"]
            case .copy: ["editionID", "locationID", "shelf", "addedAt"]
            case .location: ["name", "symbol"]
            case .loan: ["copyID", "borrower", "loanedAt", "dueAt", "returnedAt"]
            }
        }
    }
    struct Entity: Codable, Equatable, Sendable {
        var kind: Kind
        var fields: [String: Field]
        var deleted: FamilyStamp?
    }
    public let version: Int
    public let libraryID: UUID
    private var entities: [String: Entity]

    var deletedEntityIDs: Set<UUID> {
        Set(entities.compactMap { $0.value.deleted == nil ? nil : UUID(uuidString: $0.key) })
    }

    public init(snapshot: LibrarySnapshot, libraryID: UUID = UUID(), replicaID: UUID, date: Date = Date()) throws {
        try snapshot.validate()
        version = 1
        self.libraryID = libraryID
        entities = [:]
        let stamp = FamilyStamp(date: date, replicaID: replicaID, counter: 0)
        for (id, item) in try Self.flatten(snapshot) {
            entities[id] = Entity(kind: item.0, fields: item.1.mapValues { Field(value: $0, stamp: stamp) })
        }
        _ = try self.snapshot()
    }

    public func applying(_ next: LibrarySnapshot, replicaID: UUID, counter: UInt64, date: Date = Date()) throws -> Self {
        try next.validate()
        let before = try Self.flatten(snapshot())
        let after = try Self.flatten(next)
        let stamp = FamilyStamp(date: date, replicaID: replicaID, counter: counter)
        guard date.timeIntervalSince1970.isFinite else { throw FamilyError.invalidData }
        var result = self
        for (id, old) in before where after[id] == nil {
            guard var entity = result.entities[id], entity.kind == old.0 else { throw FamilyError.invalidData }
            entity.deleted = max(entity.deleted ?? stamp, stamp)
            result.entities[id] = entity
        }
        for (id, item) in after {
            if let old = result.entities[id] {
                guard old.kind == item.0 else { throw FamilyError.invalidData }
                // Reusing a permanently deleted identifier is unsafe. Restores use local mode.
                if old.deleted != nil && before[id] == nil { throw FamilyError.invalidData }
                for (key, value) in item.1 where before[id]?.1[key] != value {
                    result.entities[id]?.fields[key] = Field(value: value, stamp: stamp)
                }
            } else {
                result.entities[id] = Entity(kind: item.0, fields: item.1.mapValues { Field(value: $0, stamp: stamp) })
            }
        }
        _ = try result.snapshot()
        return result
    }

    public func merged(with other: Self) throws -> Self {
        guard libraryID == other.libraryID else { throw FamilyError.wrongLibrary }
        try validateMetadata(); try other.validateMetadata()
        var result = self
        for (id, incoming) in other.entities {
            guard var current = result.entities[id] else { result.entities[id] = incoming; continue }
            guard current.kind == incoming.kind else { throw FamilyError.invalidData }
            for (key, field) in incoming.fields {
                if let existing = current.fields[key] {
                    if field.stamp == existing.stamp && field.value != existing.value { throw FamilyError.invalidData }
                    if existing.stamp < field.stamp { current.fields[key] = field }
                } else { current.fields[key] = field }
            }
            if let deletion = incoming.deleted { current.deleted = max(current.deleted ?? deletion, deletion) }
            result.entities[id] = current
        }
        _ = try result.snapshot()
        return result
    }

    public func snapshot() throws -> LibrarySnapshot {
        try validateMetadata()
        func decode<T: Decodable>(_ kind: Kind, _ type: T.Type, includeDeleted: Bool = false) throws -> [T] {
            try entities.keys.sorted().compactMap { id in
                let entity = entities[id]!
                guard entity.kind == kind, includeDeleted || entity.deleted == nil else { return nil }
                var values = entity.fields.mapValues(\.value)
                values["id"] = .string(id)
                return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(values))
            }
        }
        let editions = try decode(.edition, BookEdition.self)
        let editionIDs = Set(editions.map(\.id))
        let allCopies = try decode(.copy, BookCopy.self)
        guard allCopies.allSatisfy({ entities[$0.editionID.uuidString]?.kind == .edition }) else { throw FamilyError.invalidData }
        let copies = allCopies.filter { editionIDs.contains($0.editionID) }
        let copyIDs = Set(copies.map(\.id))
        let referencedPlaces = Set(copies.map(\.locationID))
        let allPlaces = try decode(.location, StorageLocation.self, includeDeleted: true)
        var locations = allPlaces.filter { entities[$0.id.uuidString]?.deleted == nil || referencedPlaces.contains($0.id) }
        // Concurrent removal of different empty places must not leave a library with no place.
        if locations.isEmpty, let fallback = allPlaces.first { locations = [fallback] }
        let allLoans = try decode(.loan, BookLoan.self)
        guard allLoans.allSatisfy({ entities[$0.copyID.uuidString]?.kind == .copy }) else { throw FamilyError.invalidData }
        let loans = allLoans.filter { copyIDs.contains($0.copyID) }
        let snapshot = LibrarySnapshot(editions: editions, copies: copies, locations: locations, loans: loans)
        try snapshot.validate()
        try LibraryResourceLimits.validate(snapshot)
        return snapshot
    }

    private func validateMetadata() throws {
        guard version == 1 else { throw FamilyError.unsupportedVersion }
        guard entities.count <= 100_000 else { throw FamilyError.tooLarge }
        for (id, entity) in entities {
            guard let uuid = UUID(uuidString: id), uuid.uuidString == id,
                  Set(entity.fields.keys) == entity.kind.keys else { throw FamilyError.invalidData }
            let stamps = entity.fields.values.map(\.stamp) + [entity.deleted].compactMap { $0 }
            guard stamps.allSatisfy({ $0.date.timeIntervalSince1970.isFinite }) else { throw FamilyError.invalidData }
        }
    }

    private static func flatten(_ snapshot: LibrarySnapshot) throws -> [String: (Kind, [String: FamilyValue])] {
        var result: [String: (Kind, [String: FamilyValue])] = [:]
        func add<T: Encodable & Identifiable>(_ values: [T], kind: Kind) throws where T.ID == UUID {
            for value in values {
                var fields = try JSONDecoder().decode([String: FamilyValue].self, from: JSONEncoder().encode(value))
                fields.removeValue(forKey: "id")
                for key in kind.keys where fields[key] == nil { fields[key] = .null }
                result[value.id.uuidString] = (kind, fields)
            }
        }
        try add(snapshot.editions, kind: .edition)
        try add(snapshot.copies, kind: .copy)
        try add(snapshot.locations, kind: .location)
        try add(snapshot.loans, kind: .loan)
        return result
    }
}
