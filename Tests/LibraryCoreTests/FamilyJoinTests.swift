import XCTest
@testable import LibraryCore

final class FamilyJoinTests: XCTestCase {
    func testUndoAfterFailedJoinRestoresBookAndReferencesWithStableNewIDs() throws {
        var local = LibrarySnapshot.empty
        let book = BookEdition(title: "Restored book")
        let copy = BookCopy(editionID: book.id, locationID: local.locations[0].id)
        let loan = BookLoan(copyID: copy.id, borrower: "Family")
        local.editions = [book]; local.copies = [copy]; local.loans = [loan]
        let remote = try FamilyEnvelope(snapshot: .empty, replicaID: UUID())
        let destination = FamilySyncState(accountID: "a", zoneName: "z", zoneOwner: "o", recordName: "r", isOwner: false, envelope: remote)
        var pending = try PendingFamilyJoin(snapshot: local, destination: destination)
        var deleted = local
        deleted.editions = []; deleted.copies = []; deleted.loans = []
        for _ in 0..<2 {
            try pending.updateLocal(deleted)
            let deletionOnServer = pending.imported
            try pending.updateLocal(local)
            let restored = try pending.imported.snapshot()
            XCTAssertEqual(restored.editions.count, 1)
            XCTAssertNotEqual(restored.editions[0].id, book.id)
            XCTAssertEqual(restored.copies[0].editionID, restored.editions[0].id)
            XCTAssertEqual(restored.loans[0].copyID, restored.copies[0].id)
            XCTAssertEqual(try deletionOnServer.merged(with: pending.imported).snapshot(), restored)
            // A lost response and restart must reuse these IDs, without duplicating the import.
            pending = try JSONDecoder().decode(PendingFamilyJoin.self, from: JSONEncoder().encode(pending))
            try pending.updateLocal(local)
            XCTAssertEqual(try pending.imported.snapshot(), restored)
        }
    }

    func testRetryAfterLostAcknowledgementKeepsInterveningFamilyEdit() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        let database = try LibraryDatabase(url: path)
        var local = try database.load()
        local.editions = [BookEdition(title: "Local original")]
        try database.save(local)
        let remote = try FamilyEnvelope(snapshot: .empty, replicaID: UUID())
        let destination = FamilySyncState(accountID: "a", zoneName: "z", zoneOwner: "o", recordName: "r", isOwner: false, envelope: remote)
        let date = Date()
        let operation = try PendingFamilyJoin(snapshot: local, destination: destination, date: date)
        try database.savePendingFamilyJoin(operation)
        var uploaded = try remote.merged(with: operation.imported)
        var changed = try uploaded.snapshot()
        changed.editions[0].title = "Updated by family"
        uploaded = try uploaded.applying(changed, replicaID: UUID(), counter: 1, date: date.addingTimeInterval(10))
        let restarted = try LibraryDatabase(url: path)
        var resumed = try XCTUnwrap(restarted.loadPendingFamilyJoin())
        try resumed.updateLocal(local, date: date.addingTimeInterval(20))
        XCTAssertEqual(try uploaded.merged(with: resumed.imported).snapshot().editions[0].title, "Updated by family")
        XCTAssertEqual(try restarted.load(), local, "Preparation must not switch the visible library")
        XCTAssertNil(try restarted.loadFamilyState())
    }
}
