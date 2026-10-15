import XCTest
@testable import LibraryCore

@MainActor
final class FamilySyncTests: XCTestCase {
    func state() throws -> FamilySyncState {
        let envelope = try FamilyEnvelope(snapshot: .empty, replicaID: UUID())
        return FamilySyncState(accountID: "account-a", zoneName: "zone", zoneOwner: "owner", recordName: "root", isOwner: true, envelope: envelope)
    }

    func testSnapshotAndPendingStateSurviveRestartTogether() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try LibraryDatabase(url: url)
        var pending = try state()
        var next = try pending.envelope.snapshot()
        next.editions.append(BookEdition(title: "Offline"))
        try pending.edit(next)
        try db.save(next, familyState: pending)
        let reopened = try LibraryDatabase(url: url)
        XCTAssertEqual(try reopened.load(), next)
        XCTAssertEqual(try reopened.loadFamilyState(), pending)
        var invalid = next
        invalid.locations = []
        XCTAssertThrowsError(try db.save(invalid, familyState: pending))
        XCTAssertEqual(try reopened.loadFamilyState(), pending)
    }

    func testOwnerStopRetainsFinalCloudAndPendingLocalEditsAtomically() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try LibraryDatabase(url: url)
        var owner = try state()
        var cloud = try owner.envelope.snapshot()
        cloud.editions.append(BookEdition(title: "Last participant edit"))
        let finalCloud = try owner.envelope.applying(cloud, replicaID: UUID(), counter: 1)
        var local = try owner.envelope.snapshot()
        local.editions.append(BookEdition(title: "Owner offline edit"))
        try owner.edit(local)
        try db.save(try owner.envelope.snapshot(), familyState: owner)
        let retained = try owner.snapshotAfterStoppingSharing(finalEnvelope: finalCloud)
        try db.save(retained, familyState: nil)
        let reopened = try LibraryDatabase(url: url)
        XCTAssertNil(try reopened.loadFamilyState())
        XCTAssertEqual(Set(try reopened.load().editions.map(\.title)), ["Last participant edit", "Owner offline edit"])
        let stranger = try state().envelope
        XCTAssertThrowsError(try owner.snapshotAfterStoppingSharing(finalEnvelope: stranger))
    }

    func testFailedUploadKeepsOutboxAndLocalData() async throws {
        let box = StateBox(try state())
        var next = try box.value!.envelope.snapshot()
        next.editions.append(BookEdition(title: "Pending"))
        try box.value!.edit(next)
        let transport = FakeFamilyTransport(remote: try stateRemote(box.value!))
        transport.saveError = FamilyError.unavailable
        let engine = engine(box, transport)
        do { try await engine.sync(); XCTFail("Expected network failure") } catch {}
        XCTAssertTrue(box.value!.hasPendingChanges)
        XCTAssertEqual(try box.value!.envelope.snapshot().editions.first?.title, "Pending")
    }

    func testAccountMismatchNeverUploads() async throws {
        let box = StateBox(try state())
        let transport = FakeFamilyTransport(remote: try stateRemote(box.value!))
        transport.account = "account-b"
        do { try await engine(box, transport).sync(); XCTFail("Expected account refusal") }
        catch { XCTAssertEqual(error as? FamilyError, .accountChanged) }
        XCTAssertEqual(transport.writes, 0)
        XCTAssertEqual(box.value!.accountID, "account-a")
    }

    func testEditsDuringUploadAreNotAcknowledgedOrLost() async throws {
        let box = StateBox(try state())
        let transport = FakeFamilyTransport(remote: try stateRemote(box.value!))
        var next = try box.value!.envelope.snapshot()
        next.editions.append(BookEdition(title: "First"))
        try box.value!.edit(next)
        transport.duringSave = {
            var later = try box.value!.envelope.snapshot()
            later.editions.append(BookEdition(title: "Second"))
            try box.value!.edit(later)
        }
        try await engine(box, transport).sync()
        XCTAssertEqual(try box.value!.envelope.snapshot().editions.count, 2)
        XCTAssertTrue(box.value!.hasPendingChanges)
        XCTAssertEqual(box.value!.acknowledgedGeneration, 1)
    }

    func testReadOnlyAndRevokedRolesRejectEveryLocalEdit() throws {
        for role in [FamilyRole.reader, .revoked] {
            var restricted = try state()
            restricted.role = role
            var next = try restricted.envelope.snapshot()
            next.editions.append(BookEdition(title: "Denied"))
            XCTAssertThrowsError(try restricted.edit(next))
            XCTAssertTrue(try restricted.envelope.snapshot().editions.isEmpty)
        }
    }

    func testRevokedOwnerCanRetryVerifiedRecoveryButParticipantCannot() async throws {
        var owner = try state()
        owner.role = .revoked
        let transport = FakeFamilyTransport(remote: try stateRemote(owner))
        transport.fetchError = FamilyError.ownerStoppedSharing
        do {
            try await engine(StateBox(owner), transport).sync()
            XCTFail("Owner must retry the read so final-root recovery remains reachable")
        } catch { XCTAssertEqual(error as? FamilyError, .ownerStoppedSharing) }
        XCTAssertEqual(transport.reads, 1)
        XCTAssertEqual(transport.writes, 0)
        let participant = FamilySyncState(accountID: owner.accountID, zoneName: owner.zoneName,
                                          zoneOwner: owner.zoneOwner, recordName: owner.recordName,
                                          isOwner: false, envelope: owner.envelope, role: .revoked)
        try await engine(StateBox(participant), transport).sync()
        XCTAssertEqual(transport.reads, 1)
        XCTAssertEqual(transport.writes, 0)
    }

    func testPermissionDowngradePreservesPendingChangesWithoutUploading() async throws {
        let box = StateBox(try state())
        var next = try box.value!.envelope.snapshot()
        next.editions.append(BookEdition(title: "Offline"))
        try box.value!.edit(next)
        var remote = try stateRemote(box.value!)
        remote.role = .reader
        let transport = FakeFamilyTransport(remote: remote)
        try await engine(box, transport).sync()
        XCTAssertEqual(transport.writes, 0)
        XCTAssertEqual(box.value!.role, .reader)
        XCTAssertTrue(box.value!.hasPendingChanges)
    }

    func testLateResponseCannotReplaceAnotherSession() async throws {
        let box = StateBox(try state())
        let oldID = box.value!.sessionID
        let transport = FakeFamilyTransport(remote: try stateRemote(box.value!))
        transport.duringFetch = { box.value = try self.state() }
        do { try await engine(box, transport).sync(); XCTFail("Expected stale session") } catch {}
        XCTAssertNotEqual(box.value!.sessionID, oldID)
        XCTAssertEqual(transport.writes, 0)
    }

    func testConflictRefetchesAndRetriesWithoutDiscardingLocalEdits() async throws {
        let box = StateBox(try state())
        let transport = FakeFamilyTransport(remote: try stateRemote(box.value!))
        var next = try box.value!.envelope.snapshot()
        next.editions.append(BookEdition(title: "Retry"))
        try box.value!.edit(next)
        transport.conflicts = 1
        try await engine(box, transport).sync()
        XCTAssertEqual(transport.writes, 2)
        XCTAssertFalse(box.value!.hasPendingChanges)
        XCTAssertEqual(try box.value!.envelope.snapshot().editions[0].title, "Retry")
    }

    private func stateRemote(_ state: FamilySyncState) throws -> FamilyRemote {
        FamilyRemote(envelope: state.envelope, changeTag: "v1", role: .owner)
    }
    private func engine(_ box: StateBox, _ transport: FakeFamilyTransport) -> FamilySyncEngine {
        FamilySyncEngine(transport: transport, load: { box.value }, commit: { box.value = $0 })
    }
}

@MainActor private final class StateBox {
    var value: FamilySyncState?
    init(_ value: FamilySyncState) { self.value = value }
}

@MainActor private final class FakeFamilyTransport: FamilyTransport {
    var account = "account-a"
    var remote: FamilyRemote
    var saveError: Error?
    var fetchError: Error?
    var reads = 0
    var writes = 0
    var conflicts = 0
    var duringSave: (() throws -> Void)?
    var duringFetch: (() throws -> Void)?
    init(remote: FamilyRemote) { self.remote = remote }
    func accountID() async throws -> String { account }
    func fetch(_ state: FamilySyncState) async throws -> FamilyRemote {
        reads += 1
        if let fetchError { throw fetchError }
        try duringFetch?()
        return remote
    }
    func save(_ envelope: FamilyEnvelope, state: FamilySyncState, changeTag: String) async throws -> FamilyRemote {
        writes += 1
        if conflicts > 0 { conflicts -= 1; throw FamilyError.conflict }
        if let saveError { throw saveError }
        try duringSave?()
        remote = FamilyRemote(envelope: envelope, changeTag: "saved", role: .owner)
        return remote
    }
}
