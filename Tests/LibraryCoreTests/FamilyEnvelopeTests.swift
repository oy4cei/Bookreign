import Foundation
import XCTest
@testable import LibraryCore

final class FamilyEnvelopeTests: XCTestCase {
    let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let time = Date(timeIntervalSince1970: 1_800_000_000)

    func fixture() -> LibrarySnapshot {
        let location = StorageLocation(name: "Home")
        let book = BookEdition(title: "Original", author: "Author", language: "uk")
        return LibrarySnapshot(editions: [book], copies: [BookCopy(editionID: book.id, locationID: location.id)], locations: [location])
    }

    func testIndependentFieldsMergeWithoutLosingEitherEdit() throws {
        let original = fixture()
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var left = original, right = original
        left.editions[0].title = "New title"
        right.editions[0].notes = "Family note"
        let l = try base.applying(left, replicaID: a, counter: 1, date: time.addingTimeInterval(1))
        let r = try base.applying(right, replicaID: b, counter: 1, date: time.addingTimeInterval(2))
        let result = try l.merged(with: r).snapshot()
        XCTAssertEqual(result.editions[0].title, "New title")
        XCTAssertEqual(result.editions[0].notes, "Family note")
        XCTAssertEqual(try r.merged(with: l).snapshot(), result)
    }

    func testNewestEditAndStableTieBreakerConverge() throws {
        let original = fixture()
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var left = original, right = original
        left.editions[0].title = "Left"
        right.editions[0].title = "Right"
        let l = try base.applying(left, replicaID: a, counter: 10, date: time.addingTimeInterval(1))
        let r = try base.applying(right, replicaID: b, counter: 1, date: time.addingTimeInterval(1))
        XCTAssertEqual(try l.merged(with: r).snapshot().editions[0].title, "Right")
        let later = try base.applying(left, replicaID: a, counter: 11, date: time.addingTimeInterval(2))
        XCTAssertEqual(try r.merged(with: later).snapshot().editions[0].title, "Left")
    }

    func testDeletedBookCannotBeResurrectedByLaterOfflineEdits() throws {
        let original = fixture()
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var removed = original, offline = original
        removed.editions = []; removed.copies = []
        offline.editions[0].notes = "Offline"
        let deletion = try base.applying(removed, replicaID: a, counter: 1, date: time.addingTimeInterval(1))
        let stale = try base.applying(offline, replicaID: b, counter: 1, date: time.addingTimeInterval(2))
        let merged = try deletion.merged(with: stale)
        XCTAssertTrue(try merged.snapshot().editions.isEmpty)
        XCTAssertTrue(try merged.snapshot().copies.isEmpty)
        XCTAssertEqual(try merged.merged(with: base).snapshot(), try merged.snapshot())
    }

    func testDeletionCascadesToConcurrentlyCreatedLoan() throws {
        let original = fixture()
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var removed = original, offline = original
        removed.copies = []
        offline.loans = [BookLoan(copyID: original.copies[0].id, borrower: "Friend", loanedAt: time)]
        let deletion = try base.applying(removed, replicaID: a, counter: 1, date: time.addingTimeInterval(1))
        let loan = try base.applying(offline, replicaID: b, counter: 1, date: time.addingTimeInterval(2))
        XCTAssertTrue(try deletion.merged(with: loan).snapshot().loans.isEmpty)
    }

    func testReferencedLocationSurvivesConcurrentDeletion() throws {
        var original = fixture()
        let unused = StorageLocation(name: "Cabin")
        original.locations.append(unused)
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var removed = original, moved = original
        removed.locations.removeAll { $0.id == unused.id }
        moved.copies[0].locationID = unused.id
        let deletion = try base.applying(removed, replicaID: a, counter: 1, date: time.addingTimeInterval(1))
        let move = try base.applying(moved, replicaID: b, counter: 1, date: time.addingTimeInterval(2))
        let result = try deletion.merged(with: move).snapshot()
        XCTAssertEqual(result.copies[0].locationID, unused.id)
        XCTAssertTrue(result.locations.contains { $0.id == unused.id })
        try result.validate()
    }

    func testIncompatibleLoansFailWithoutMutatingEitherEnvelope() throws {
        let original = fixture()
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var left = original, right = original
        left.loans = [BookLoan(copyID: original.copies[0].id, borrower: "A", loanedAt: time)]
        right.loans = [BookLoan(copyID: original.copies[0].id, borrower: "B", loanedAt: time)]
        let l = try base.applying(left, replicaID: a, counter: 1, date: time.addingTimeInterval(1))
        let r = try base.applying(right, replicaID: b, counter: 1, date: time.addingTimeInterval(2))
        XCTAssertThrowsError(try l.merged(with: r))
        XCTAssertEqual(try l.snapshot().loans[0].borrower, "A")
        XCTAssertEqual(try r.snapshot().loans[0].borrower, "B")
    }

    func testJoinKeepsDifferentCopiesWithSameISBN() throws {
        let original = fixture()
        var second = fixture()
        second.editions[0].isbn = original.editions[0].isbn
        let base = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        let imported = try FamilyEnvelope(snapshot: second, libraryID: base.libraryID, replicaID: b, date: time)
        let merged = try base.merged(with: imported).snapshot()
        XCTAssertEqual(merged.editions.count, 2)
        XCTAssertEqual(merged.copies.count, 2)
    }

    func testWrongLibraryCannotBeMerged() throws {
        let l = try FamilyEnvelope(snapshot: fixture(), replicaID: a, date: time)
        let r = try FamilyEnvelope(snapshot: fixture(), replicaID: b, date: time)
        XCTAssertThrowsError(try l.merged(with: r))
    }

    func testCodecRoundTripAndCorruptionRejection() throws {
        let envelope = try FamilyEnvelope(snapshot: fixture(), replicaID: a, date: time)
        let data = try FamilyAssetCodec.encode(envelope)
        XCTAssertEqual(try FamilyAssetCodec.decode(data), envelope)
        var corrupt = data
        corrupt[corrupt.count - 1] ^= 0xff
        XCTAssertThrowsError(try FamilyAssetCodec.decode(corrupt))
        XCTAssertThrowsError(try FamilyAssetCodec.decode(data.prefix(10)))
        XCTAssertThrowsError(try FamilyAssetCodec.decode(data, maximumBytes: 32))
    }

    func testUnknownEnvelopeVersionAndMissingFieldsAreRejected() throws {
        let envelope = try FamilyEnvelope(snapshot: fixture(), replicaID: a, date: time)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
        json["version"] = 999
        let unknown = try JSONDecoder().decode(FamilyEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try unknown.snapshot())
    }

    func testUnknownParentIsRejectedRatherThanSilentlyDroppingCopy() throws {
        let original = fixture()
        let envelope = try FamilyEnvelope(snapshot: original, replicaID: a, date: time)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
        var entities = try XCTUnwrap(json["entities"] as? [String: Any])
        entities.removeValue(forKey: original.editions[0].id.uuidString)
        json["entities"] = entities
        let broken = try JSONDecoder().decode(FamilyEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try broken.snapshot())
    }
}
