import SwiftUI
import CloudKit
import Combine
import LibraryCore

struct FamilyShareCallbackContext {
    let sessionID: UUID
    let accountID: String
    let epoch: UUID
    let shareID: CKRecord.ID
}

@MainActor
final class FamilySharingCoordinator: ObservableObject {
    @Published var busy = false
    @Published var issue: String?
    @Published var invitation: CKShare.Metadata?
    @Published var presentedShare: CKShare?
    private unowned let store: LibraryStore
    let transport = CloudKitFamilyTransport()
    private var task: Task<Void, Never>?
    private var sessionEpoch = UUID()
    private var accountObserver: AnyCancellable?
    private lazy var engine = FamilySyncEngine(transport: transport, load: { [weak self] in self?.store.familyState }, commit: { [weak self] state in
        guard let self else { throw CancellationError() }
        try self.store.commitFamily(state)
    })

    init(store: LibraryStore) {
        self.store = store
        accountObserver = NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor in self?.accountChanged() }
            }
    }

    var status: String {
        if busy { return L("Синхронизация…") }
        if let issue { return issue }
        guard let state = store.familyState else { return L("Библиотека только на этом устройстве") }
        if state.role == .revoked { return L("Общий доступ завершён. Копия доступна для чтения и экспорта.") }
        if !store.familyAccountReady { return L("Требуется прежний аккаунт iCloud") }
        if state.isCreating { return L("Включение не завершено. Можно повторить.") }
        return state.hasPendingChanges ? L("Изменения ожидают отправки") : L("Синхронизировано")
    }

    func accountChanged() {
        sessionEpoch = UUID()
        task?.cancel(); task = nil
        transport.reset()
        store.familyAccountReady = false
        busy = false
        presentedShare = nil
        issue = L("Требуется прежний аккаунт iCloud")
        scheduleSync(immediately: true)
    }

    func scheduleSync(immediately: Bool = false) {
        guard store.familyState != nil else { return }
        // Do not cancel an upload on each keystroke. The generation check retains newer work.
        guard task == nil else { return }
        let epoch = sessionEpoch
        task = Task { [weak self] in
            guard let self else { return }
            if !immediately { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled, epoch == self.sessionEpoch else { return }
            await self.synchronize()
            guard epoch == self.sessionEpoch else { return }
            self.task = nil
            if self.issue == nil, self.store.familyState?.hasPendingChanges == true,
               self.store.familyState?.canEdit == true { self.scheduleSync() }
        }
    }

    func synchronize() async {
        guard !busy, let initial = store.familyState else { return }
        busy = true; issue = nil
        let epoch = sessionEpoch
        defer { if epoch == sessionEpoch { busy = false } }
        do {
            guard try await transport.accountID() == initial.accountID else { throw FamilyError.accountChanged }
            try check(epoch)
            store.familyAccountReady = true
            if initial.isCreating {
                let (remote, share) = try await transport.create(initial)
                try check(epoch)
                guard var latest = store.familyState, latest.sessionID == initial.sessionID else { throw FamilyError.accountChanged }
                latest.envelope = try latest.envelope.merged(with: remote.envelope)
                latest.isCreating = false
                latest.lastSync = Date()
                try store.commitFamily(latest)
                presentedShare = share
            }
            try await engine.sync()
            try check(epoch)
            if let current = store.familyState {
                // Push delivery is optional; foreground/manual refresh still works if this fails.
                try? await transport.subscribe(current)
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            guard epoch == sessionEpoch else { return }
            if initial.isOwner, let failure = error as? FamilyError,
               failure == .ownerStoppedSharing || failure == .revoked {
                do {
                    try await finishOwnerSharing(initial, epoch: epoch)
                } catch {
                    guard epoch == sessionEpoch else { return }
                    if (error as? FamilyError) == .accountChanged { store.familyAccountReady = false }
                    issue = familyErrorText(error)
                }
                return
            }
            if (error as? FamilyError) == .accountChanged { store.familyAccountReady = false }
            issue = familyErrorText(error)
        }
    }

    func enable() async {
        guard !busy, store.isReady, store.familyState == nil else { return }
        busy = true; issue = nil
        let epoch = sessionEpoch
        do {
            let account = try await transport.accountID()
            try check(epoch)
            let envelope = try FamilyEnvelope(snapshot: store.snapshot, replicaID: UUID())
            let state = FamilySyncState(accountID: account, zoneName: "Bookreign-" + envelope.libraryID.uuidString,
                                        zoneOwner: CKCurrentUserDefaultName, recordName: envelope.libraryID.uuidString,
                                        isOwner: true, envelope: envelope, isCreating: true)
            try store.commitFamily(state)
            store.familyAccountReady = true
        } catch {
            if epoch == sessionEpoch {
                issue = (error as? FamilyError) == .accountChanged
                    ? L("Войдите в iCloud в настройках устройства, затем повторите включение.")
                    : familyErrorText(error)
            }
        }
        guard epoch == sessionEpoch else { return }
        busy = false
        if store.familyState != nil { await synchronize() }
    }

    func receive(_ metadata: CKShare.Metadata) {
        guard !busy else { return }
        guard metadata.containerIdentifier == CloudKitFamilyTransport.containerIdentifier else { return }
        guard store.familyState == nil else {
            issue = L("На устройстве уже открыта общая библиотека. Сначала завершите текущий доступ.")
            return
        }
        invitation = metadata
    }

    func join(mergeLocal: Bool, exportedSnapshot: LibrarySnapshot? = nil) async {
        guard !busy, store.familyState == nil, let metadata = invitation else { return }
        guard mergeLocal || exportedSnapshot == store.snapshot else { issue = L("Сначала сохраните текущую библиотеку в Файлы."); return }
        busy = true; issue = nil
        store.familyTransitionInProgress = true
        let epoch = sessionEpoch
        defer {
            store.familyTransitionInProgress = false
            if epoch == sessionEpoch { busy = false }
        }
        do {
            var state = try await transport.accept(metadata)
            try check(epoch)
            guard store.familyState == nil else { throw FamilyError.wrongLibrary }
            guard mergeLocal || exportedSnapshot == store.snapshot else { throw FamilyError.conflict }
            if mergeLocal {
                guard state.canEdit else { throw FamilyError.readOnly }
                let local = try store.prepareFamilyJoin(state)
                let merged = try state.envelope.merged(with: local).snapshot()
                try state.edit(merged)
                // Keep the old database until CloudKit confirms the entire joined snapshot.
                // A failed/lost response can be retried with the same stable record IDs.
                var joining = state
                let joinEngine = FamilySyncEngine(transport: transport, load: { joining }, commit: { joining = $0 })
                try await joinEngine.sync()
                guard !joining.hasPendingChanges, joining.canEdit else { throw FamilyError.readOnly }
                state = joining
            }
            try check(epoch)
            // Commit only after all downloads, validation and optional merge succeed.
            try store.commitFamily(state)
            store.familyAccountReady = true
            invitation = nil
            scheduleSync(immediately: true)
        } catch { if epoch == sessionEpoch { issue = familyErrorText(error) } }
    }

    func manage() async {
        guard !busy, let state = store.familyState, !state.isCreating else { return }
        busy = true; issue = nil
        let epoch = sessionEpoch
        defer { if epoch == sessionEpoch { busy = false } }
        do {
            let share = try await transport.sharingRecord(state)
            try check(epoch)
            presentedShare = share
        } catch { if epoch == sessionEpoch { issue = familyErrorText(error) } }
    }

    func callbackContext(for share: CKShare) -> FamilyShareCallbackContext? {
        guard let state = store.familyState else { return nil }
        return FamilyShareCallbackContext(sessionID: state.sessionID, accountID: state.accountID,
                                          epoch: sessionEpoch, shareID: share.recordID)
    }

    func sharingSaved(_ context: FamilyShareCallbackContext?, shareID: CKRecord.ID?) async {
        guard await acceptsCallback(context, shareID: shareID) else { return }
        scheduleSync(immediately: true)
    }

    func sharingFailed(_ context: FamilyShareCallbackContext?, shareID: CKRecord.ID?, error: Error) async {
        guard await acceptsCallback(context, shareID: shareID) else { return }
        issue = familyErrorText(error)
    }

    private func acceptsCallback(_ context: FamilyShareCallbackContext?, shareID: CKRecord.ID?) async -> Bool {
        guard let context, shareID == context.shareID, context.epoch == sessionEpoch,
              store.familyState?.sessionID == context.sessionID, store.familyState?.accountID == context.accountID else { return false }
        do {
            guard try await transport.accountID() == context.accountID else { return false }
            try check(context.epoch)
            return store.familyState?.sessionID == context.sessionID
        } catch { return false }
    }

    func sharingStopped(_ context: FamilyShareCallbackContext?, shareID: CKRecord.ID?) async {
        guard await acceptsCallback(context, shareID: shareID), let state = store.familyState else { return }
        sessionEpoch = UUID(); task?.cancel(); task = nil; busy = true
        let epoch = sessionEpoch
        defer { if epoch == sessionEpoch { busy = false } }
        presentedShare = nil
        do {
            if state.isOwner { try await finishOwnerSharing(state, epoch: epoch) }
            else { var revoked = state; revoked.role = .revoked; try store.commitFamily(revoked) }
            issue = nil
        } catch {
            guard epoch == sessionEpoch else { return }
            if (error as? FamilyError) == .accountChanged { store.familyAccountReady = false }
            issue = familyErrorText(error)
        }
    }

    private func finishOwnerSharing(_ initial: FamilySyncState, epoch: UUID) async throws {
        let finalEnvelope = try await transport.finalOwnerEnvelope(initial)
        try check(epoch)
        guard let latest = store.familyState, latest.sessionID == initial.sessionID,
              latest.accountID == initial.accountID else { throw FamilyError.accountChanged }
        // The store merges against its latest state, including edits made during download.
        try store.keepOwnerLibraryLocally(finalEnvelope: finalEnvelope)
        transport.reset(); presentedShare = nil; issue = nil
    }

    func cancelCreation() async {
        guard !busy, let state = store.familyState, state.isCreating else { return }
        busy = true; issue = nil
        let epoch = sessionEpoch
        defer { if epoch == sessionEpoch { busy = false } }
        do {
            try await transport.cancelCreation(state)
            try check(epoch)
            try store.keepOwnerLibraryLocally()
            transport.reset()
        } catch { if epoch == sessionEpoch { issue = familyErrorText(error) } }
    }

    func discardRevokedCopy() {
        guard !busy else { return }
        do {
            try store.discardRevokedFamilyCopy()
            sessionEpoch = UUID(); task?.cancel(); task = nil
            transport.reset(); issue = nil
        } catch { issue = familyErrorText(error) }
    }
    private func check(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard epoch == sessionEpoch else { throw FamilyError.accountChanged }
    }
}

@MainActor func familyErrorText(_ error: Error) -> String {
    if let error = error as? FamilyError {
        switch error {
        case .accountChanged: return L("Требуется прежний аккаунт iCloud")
        case .readOnly: return L("Общая библиотека доступна только для чтения. Проверьте iCloud и права доступа.")
        case .revoked, .ownerStoppedSharing: return L("Общий доступ завершён. Копия доступна для чтения и экспорта.")
        case .tooLarge: return L("Данные слишком большие. Локальная библиотека сохранена.")
        case .conflict: return L("Библиотека сейчас меняется. Повторите синхронизацию.")
        case .invalidData, .unsupportedVersion, .wrongLibrary: return L("Общие данные не удалось проверить. Локальная библиотека сохранена. Обновите приложение и повторите.")
        case .unavailable: return L("Не удалось синхронизировать. Локальные изменения сохранены.")
        }
    }
    if let cloud = error as? CKError {
        if cloud.code == .quotaExceeded { return L("В iCloud владельца недостаточно места. Локальные изменения сохранены.") }
        if cloud.code == .networkUnavailable || cloud.code == .networkFailure { return L("Ожидает сети. Локальные изменения сохранены.") }
    }
    if error is LibraryDataError { return L("Общие данные не удалось проверить. Локальная библиотека сохранена. Обновите приложение и повторите.") }
    return L("Не удалось синхронизировать. Локальные изменения сохранены.")
}
