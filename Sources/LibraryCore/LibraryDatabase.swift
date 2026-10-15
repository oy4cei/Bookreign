import Foundation
import SQLite3

public enum LibraryDatabaseError: Error, LocalizedError, Sendable {
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): return "Ошибка базы данных: \(message)"
        }
    }
}

public final class LibraryDatabase {
    private let connection: OpaquePointer
    private let lock = NSLock()

    public init(url: URL) throws {
        var opened: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Не удалось открыть файл"
            if let opened { sqlite3_close_v2(opened) }
            throw LibraryDatabaseError.sqlite(message)
        }
        connection = opened
        do {
            try prepareSchema()
        } catch {
            sqlite3_close_v2(opened)
            throw error
        }
    }

    deinit {
        sqlite3_close_v2(connection)
    }

    public func load() throws -> LibrarySnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot = try readSnapshot() else {
            throw LibraryDataError.invalid("В базе отсутствуют данные библиотеки")
        }
        return snapshot
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try save(snapshot, familyState: nil)
    }

    public func loadFamilyState() throws -> FamilySyncState? {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM family_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw sqliteError() }
        let state = try JSONDecoder().decode(FamilySyncState.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        try state.validate()
        guard try readSnapshot() == state.envelope.snapshot() else { throw FamilyError.invalidData }
        return state
    }

    public func save(_ snapshot: LibrarySnapshot, familyState: FamilySyncState?) throws {
        try snapshot.validate()
        if let familyState {
            try familyState.validate()
            guard try familyState.envelope.snapshot() == snapshot else { throw FamilyError.invalidData }
        }
        let familyData = try familyState.map { try JSONEncoder().encode($0) }
        let data = try JSONEncoder().encode(snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LibraryDataError.invalid("Не удалось закодировать данные библиотеки")
        }
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try writeJSON(json)
            try execute("DELETE FROM family_state WHERE id = 1")
            if let familyData {
                try execute("DELETE FROM pending_family_join WHERE id = 1")
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(connection, "INSERT INTO family_state (id, payload) VALUES (1, ?)", -1, &statement, nil) == SQLITE_OK else { throw sqliteError() }
                defer { sqlite3_finalize(statement) }
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let result = familyData.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
                guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func loadPendingFamilyJoin() throws -> PendingFamilyJoin? {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM pending_family_join WHERE id = 1", -1, &statement, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw sqliteError() }
        let pending = try JSONDecoder().decode(PendingFamilyJoin.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        try pending.validate()
        return pending
    }

    public func savePendingFamilyJoin(_ pending: PendingFamilyJoin) throws {
        try pending.validate()
        let data = try JSONEncoder().encode(pending)
        guard data.count <= Int32.max else { throw FamilyError.tooLarge }
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "INSERT OR REPLACE INTO pending_family_join (id, payload) VALUES (1, ?)", -1, &statement, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }

    private func prepareSchema() throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError() }
        let version = Int(sqlite3_column_int(statement, 0))
        guard version == 0 || version == 1 else { throw LibraryDataError.unsupportedVersion(version) }
        // Auxiliary metadata keeps existing v1 snapshots readable. It is never a second outbox file.
        try execute("CREATE TABLE IF NOT EXISTS family_state (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS pending_family_join (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
        if version == 1 {
            guard try readSnapshot() != nil else {
                throw LibraryDataError.invalid("В базе отсутствуют данные библиотеки")
            }
            return
        }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("CREATE TABLE IF NOT EXISTS library_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)")
            if try readSnapshot() == nil {
                let initial = LibrarySnapshot.empty
                let data = try JSONEncoder().encode(initial)
                try writeJSON(String(decoding: data, as: UTF8.self))
            }
            try execute("PRAGMA user_version = 1")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func readSnapshot() throws -> LibrarySnapshot? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM library_snapshot WHERE id = 1", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw sqliteError()
        }
        let data = Data(String(cString: text).utf8)
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }

    private func writeJSON(_ json: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "INSERT OR REPLACE INTO library_snapshot (id, payload) VALUES (1, ?)", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bindStatus = json.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        guard bindStatus == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError()
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection))
            throw LibraryDatabaseError.sqlite(message)
        }
    }

    private func sqliteError() -> LibraryDatabaseError {
        .sqlite(String(cString: sqlite3_errmsg(connection)))
    }
}
