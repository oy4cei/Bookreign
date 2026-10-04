import Foundation
import SQLite3
import XCTest
@testable import LibraryCore

final class LibraryCoreTests: XCTestCase {
    func testNewDatabaseStartsWithUsableLocationsAndPersistsDistinctCopies() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        var snapshot = try database.load()
        XCTAssertEqual(snapshot.locations.map(\.name), ["Дом", "Дача"])

        let edition = BookEdition(title: "Кобзар", author: "Тарас Шевченко", isbn: "9789660000000", language: "uk")
        snapshot.editions.append(edition)
        snapshot.copies.append(BookCopy(editionID: edition.id, locationID: snapshot.locations[0].id, shelf: "2"))
        snapshot.copies.append(BookCopy(editionID: edition.id, locationID: snapshot.locations[1].id))
        try database.save(snapshot)

        let reopened = try LibraryDatabase(url: url).load()
        XCTAssertEqual(reopened, snapshot)
        XCTAssertEqual(reopened.copies.count, 2)
        XCTAssertEqual(Set(reopened.copies.map(\.editionID)), [edition.id])
    }

    func testSearchNormalizesCaseAndApostropheWithoutLosingUkrainianLetters() {
        let edition = BookEdition(title: "П’ять історій про Їжака", author: "Євген Ґуць", isbn: "978-966-123", language: "uk")
        let snapshot = LibrarySnapshot(editions: [edition])
        XCTAssertTrue(snapshot.matches(edition, query: "П'ЯТЬ"))
        XCTAssertTrue(snapshot.matches(edition, query: "ґуць"))
        XCTAssertTrue(snapshot.matches(edition, query: "978-966"))
        XCTAssertTrue(snapshot.matches(edition, query: "978966"))
        XCTAssertFalse(snapshot.matches(edition, query: "ежака"))
    }

    func testValidationRejectsDanglingCopiesAndDuplicateIdentifiers() {
        let location = StorageLocation(name: "Дом")
        let edition = BookEdition(title: "Книга")
        let invalidCopy = BookCopy(editionID: UUID(), locationID: location.id)
        XCTAssertThrowsError(try LibrarySnapshot(editions: [edition], copies: [invalidCopy], locations: [location]).validate())
        XCTAssertThrowsError(try LibrarySnapshot(editions: [edition, edition], locations: [location]).validate())
    }

    func testEmptyLocationListCannotBeSavedOrRestored() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        let original = try database.load()
        let noLocations = LibrarySnapshot()
        XCTAssertThrowsError(try noLocations.validate())
        XCTAssertThrowsError(try database.save(noLocations))

        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: LibraryBackup.encode(original)) as? [String: Any])
        var contents = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        contents["locations"] = []
        envelope["snapshot"] = contents
        XCTAssertThrowsError(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)))
        XCTAssertEqual(try database.load(), original)
    }

    func testUnsupportedEditionLanguageCannotBeSavedOrRestored() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        let original = try database.load()
        let edition = BookEdition(title: "Buch", language: "de")
        let unsupported = LibrarySnapshot(editions: [edition], locations: original.locations)
        XCTAssertThrowsError(try unsupported.validate())
        XCTAssertThrowsError(try database.save(unsupported))

        let validEdition = BookEdition(title: "Buch", language: "other")
        let backup = try LibraryBackup.encode(LibrarySnapshot(editions: [validEdition], locations: original.locations))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var contents = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        var editionRecord = try XCTUnwrap((contents["editions"] as? [[String: Any]])?.first)
        editionRecord["language"] = "de"
        contents["editions"] = [editionRecord]
        envelope["snapshot"] = contents
        XCTAssertThrowsError(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)))
        XCTAssertEqual(try database.load(), original)
    }

    func testLoanHistoryKeepsOnlyOneActiveLoanPerCopyAndPreservesLocation() throws {
        let location = StorageLocation(name: "Дом")
        let edition = BookEdition(title: "Книга")
        let copy = BookCopy(editionID: edition.id, locationID: location.id)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let returned = BookLoan(copyID: copy.id, borrower: "Анна", loanedAt: now, returnedAt: now.addingTimeInterval(60))
        let active = BookLoan(copyID: copy.id, borrower: "Олег", loanedAt: now.addingTimeInterval(120))
        let valid = LibrarySnapshot(editions: [edition], copies: [copy], locations: [location], loans: [returned, active])
        try valid.validate()
        XCTAssertEqual(valid.activeLoan(for: copy.id), active)
        XCTAssertEqual(valid.copies[0].locationID, location.id)
        var invalid = valid
        invalid.loans.append(BookLoan(copyID: copy.id, borrower: "Ира", loanedAt: now.addingTimeInterval(180)))
        XCTAssertThrowsError(try invalid.validate())
        invalid = valid
        invalid.loans[1].dueAt = now
        XCTAssertThrowsError(try invalid.validate())
    }

    func testBackupRejectsUnsupportedAndDanglingDataBeforeDatabaseChanges() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        let original = try database.load()
        let encoded = try LibraryBackup.encode(original)
        XCTAssertEqual(try LibraryBackup.decode(encoded), original)

        var unsupportedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        unsupportedObject["version"] = 2
        let unsupported = try JSONSerialization.data(withJSONObject: unsupportedObject)
        XCTAssertThrowsError(try LibraryBackup.decode(unsupported))
        let dangling = LibrarySnapshot(copies: [BookCopy(editionID: UUID(), locationID: original.locations[0].id)], locations: original.locations)
        XCTAssertThrowsError(try LibraryBackup.encode(dangling))
        XCTAssertThrowsError(try database.save(dangling))
        XCTAssertEqual(try database.load(), original)
    }

    func testCSVQuotesMultilineDataAndProtectsFormulaCells() {
        let edition = BookEdition(title: "=SUM(1,2)\nВторая строка", author: "Иван \"Тест\"", isbn: "+123", language: "ru")
        let location = StorageLocation(name: "Дом")
        let copy = BookCopy(editionID: edition.id, locationID: location.id, shelf: "1")
        let csv = LibraryBackup.csv(LibrarySnapshot(editions: [edition], copies: [copy], locations: [location]))
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("\"'=SUM(1,2)\nВторая строка\""))
        XCTAssertTrue(csv.contains("\"Иван \"\"Тест\"\"\""))
        XCTAssertTrue(csv.contains("'+123"))
        XCTAssertTrue(csv.contains("Дом"))
    }

    func testCorruptDatabaseIsReportedWithoutReplacingItsContents() throws {
        let url = temporaryDatabaseURL()
        let original = Data("this is not SQLite".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try LibraryDatabase(url: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDatabaseRejectsInvalidStoredSnapshotWithoutResettingIt() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        let invalidJSON = "{\"editions\":[],\"copies\":[],\"locations\":[],\"loans\":[]}"
        XCTAssertEqual(sqlite3_exec(connection, "UPDATE library_snapshot SET payload = '\(invalidJSON)' WHERE id = 1", nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try database.load())
        XCTAssertThrowsError(try LibraryDatabase(url: url))
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(connection, "SELECT payload FROM library_snapshot WHERE id = 1", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), invalidJSON)
    }

    func testRestoreRejectsDuplicateIDsAndDanglingReferences() throws {
        let edition = BookEdition(title: "Книга")
        let location = StorageLocation(name: "Дом")
        let encoded = try LibraryBackup.encode(LibrarySnapshot(editions: [edition], locations: [location]))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var contents = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        let editionRecord = try XCTUnwrap((contents["editions"] as? [[String: Any]])?.first)
        contents["editions"] = [editionRecord, editionRecord]
        envelope["snapshot"] = contents
        XCTAssertThrowsError(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)))

        contents["editions"] = [editionRecord]
        contents["copies"] = [[
            "id": UUID().uuidString, "editionID": UUID().uuidString,
            "locationID": location.id.uuidString, "shelf": "", "addedAt": 0
        ]]
        envelope["snapshot"] = contents
        XCTAssertThrowsError(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testDifferentTranslationsWithSameISBNRemainSeparateEditions() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try LibraryDatabase(url: url)
        var snapshot = try db.load()
        let ukrainian = BookEdition(title: "Маленький принц", isbn: "978123", language: "uk")
        let russian = BookEdition(title: "Маленький принц", isbn: "978123", language: "ru")
        snapshot.editions = [ukrainian, russian]
        try db.save(snapshot)

        let restored = try LibraryDatabase(url: url).load()
        XCTAssertEqual(restored.editions.map(\.language), ["uk", "ru"])
        XCTAssertNotEqual(restored.editions[0].id, restored.editions[1].id)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("polka-\(UUID().uuidString).sqlite")
    }
}
