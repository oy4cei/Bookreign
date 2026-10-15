import Foundation

@MainActor public final class FamilySyncEngine {
    private let transport: any FamilyTransport
    private let load: () -> FamilySyncState?
    private let commit: (FamilySyncState) throws -> Void
    private var running = false

    public init(transport: any FamilyTransport, load: @escaping () -> FamilySyncState?, commit: @escaping (FamilySyncState) throws -> Void) {
        self.transport = transport; self.load = load; self.commit = commit
    }

    public func sync() async throws {
        guard !running, let initial = load(), !initial.isCreating,
              initial.role != .revoked || initial.isOwner else { return }
        running = true
        defer { running = false }
        for attempt in 0..<3 {
            do {
                try await checkAccount(initial)
                let remote = try await transport.fetch(initial)
                try await checkAccount(initial)
                var current = try currentSession(initial)
                guard remote.envelope.libraryID == current.envelope.libraryID else { throw FamilyError.wrongLibrary }
                current.role = remote.role
                // Permission changes must survive even an incompatible data merge.
                try commit(current)
                current.envelope = try current.envelope.merged(with: remote.envelope)
                // Persist fetched data/permission first. Pending local work remains exportable.
                try commit(current)
                if !current.hasPendingChanges || !current.canEdit {
                    current.lastSync = Date()
                    try commit(current)
                    return
                }
                let sentGeneration = current.generation
                try await checkAccount(initial)
                let saved = try await transport.save(current.envelope, state: current, changeTag: remote.changeTag)
                try await checkAccount(initial)
                var latest = try currentSession(initial)
                latest.envelope = try latest.envelope.merged(with: saved.envelope)
                latest.role = saved.role
                latest.acknowledgedGeneration = max(latest.acknowledgedGeneration, sentGeneration)
                latest.lastSync = Date()
                try commit(latest)
                return
            } catch FamilyError.conflict where attempt < 2 {
                continue
            } catch FamilyError.revoked {
                try await checkAccount(initial)
                var latest = try currentSession(initial)
                latest.role = .revoked
                try commit(latest)
                throw FamilyError.revoked
            } catch FamilyError.readOnly {
                try await checkAccount(initial)
                var latest = try currentSession(initial)
                latest.role = .reader
                try commit(latest)
                throw FamilyError.readOnly
            }
        }
        throw FamilyError.conflict
    }

    private func currentSession(_ initial: FamilySyncState) throws -> FamilySyncState {
        try Task.checkCancellation()
        guard let current = load(), current.sessionID == initial.sessionID,
              current.accountID == initial.accountID else { throw FamilyError.accountChanged }
        return current
    }
    private func checkAccount(_ initial: FamilySyncState) async throws {
        guard try await transport.accountID() == initial.accountID else { throw FamilyError.accountChanged }
        _ = try currentSession(initial)
    }
}
