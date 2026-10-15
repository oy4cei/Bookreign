import SwiftUI
import CloudKit
import LibraryCore

struct FamilySettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var family: FamilySharingCoordinator
    @State private var consent = false
    @State private var discard = false

    var body: some View {
        Form {
            Section {
                Label(L("Вся библиотека вместе"), systemImage: "person.2.fill")
                Text(L("Семья увидит все книги, места, заметки, фотографии обложек и историю выдачи, включая имена получателей. Вход — через iCloud, без отдельной регистрации."))
                    .font(.subheadline).foregroundStyle(Color.archiveSecondary)
            }.archiveRow()
            Section {
                if family.busy { ProgressView() }
                Text(family.status).accessibilityIdentifier("familySyncStatus")
                if let state = store.familyState {
                    if let date = state.lastSync { LabeledContent(L("Последнее обновление"), value: L10n.date(date)) }
                    Text(state.role == .reader || state.role == .revoked ? L("Только чтение") : L("Можно изменять"))
                    Button(L("Обновить сейчас")) { family.scheduleSync(immediately: true) }.disabled(family.busy)
                    if state.isCreating {
                        Button(L("Повторить включение")) { Task { await family.synchronize() } }.disabled(family.busy)
                        Button(L("Отменить включение")) { Task { await family.cancelCreation() } }.disabled(family.busy)
                    } else if state.role != .revoked {
                        Button(L("Пригласить и управлять доступом"), systemImage: "person.badge.plus") {
                            Task { await family.manage() }
                        }.disabled(family.busy)
                    } else {
                        Button(L("Удалить копию с этого устройства"), role: .destructive) { discard = true }.disabled(family.busy)
                        Text(L("Резервную копию можно сохранить в настройках, в разделе «Ваши данные»."))
                            .font(.footnote).foregroundStyle(Color.archiveSecondary)
                    }
                } else {
                    Button(L("Включить семейный доступ"), systemImage: "icloud.and.arrow.up") { consent = true }
                        .disabled(family.busy || !store.isReady).accessibilityIdentifier("enableFamilyButton")
                }
            } header: { Text(L("Семейный доступ")) } footer: {
                Text(L("Приглашайте только выбранных людей. Права чтения и изменения настраиваются в окне Apple. После отзыва доступа уже скачанные и экспортированные копии остаются у участников."))
            }.archiveRow()
            Section {
                Text(L("Общая библиотека занимает место в iCloud владельца. Без интернета уже загруженные книги остаются на устройстве, а изменения отправятся после подключения."))
                Text(L("После перезапуска редактирование общей библиотеки доступно, когда приложение проверит прежний аккаунт iCloud. Сохранённые книги можно читать и экспортировать сразу."))
                Text(L("Если одну запись изменят одновременно, сохраняется последняя правка. Восстановление всей базы и отмена изменений доступны только в локальной библиотеке; экспорт доступен всегда."))
            }.font(.footnote).foregroundStyle(Color.archiveSecondary).archiveRow()
        }
        .archiveScreen().navigationTitle(L("Семейный доступ")).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("Открыть семье всю библиотеку?"), isPresented: $consent, titleVisibility: .visible) {
            Button(L("Продолжить с iCloud")) { Task { await family.enable() } }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("В iCloud будут загружены все книги, заметки, места, обложки и история выдачи. Доступ получат только приглашённые вами участники."))
        }
        .sheet(isPresented: Binding(get: { family.presentedShare != nil }, set: { if !$0 { family.presentedShare = nil } })) {
            if let share = family.presentedShare {
                FamilySharingController(share: share, family: family)
            }
        }
        .confirmationDialog(L("Удалить локальную копию общей библиотеки?"), isPresented: $discard, titleVisibility: .visible) {
            Button(L("Удалить копию"), role: .destructive) { family.discardRevokedCopy() }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("Книги и ожидающие отправки правки будут удалены с этого устройства. Сначала сохраните резервную копию. Библиотека других участников останется без изменений."))
        }
        .onAppear { family.scheduleSync(immediately: true) }
    }
}

struct FamilyJoinView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var family: FamilySharingCoordinator
    @State private var exporting = false
    @State private var document = LibraryFile(data: Data())
    @State private var exportingSnapshot: LibrarySnapshot?
    @State private var exportedSnapshot: LibrarySnapshot?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("Приглашение в семейную библиотеку"))
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(L("На устройстве будет одна общая библиотека. Выберите, что сделать с текущими книгами."))
                }.archiveRow()
                Section {
                    Button(L("Добавить мои книги в общую библиотеку")) {
                        Task { await family.join(mergeLocal: true) }
                    }.disabled(family.invitation?.participantPermission != .readWrite || family.busy)
                    Text(L("Вместе с книгами семья увидит ваши заметки, места, обложки и имена получателей. Издания с одинаковым ISBN автоматически не объединяются."))
                        .font(.footnote).foregroundStyle(Color.archiveSecondary)
                }.archiveRow()
                Section {
                    Button(L("Сохранить текущую библиотеку в Файлы")) {
                        do {
                            exportingSnapshot = store.snapshot
                            document = LibraryFile(data: try LibraryBackup.encode(store.snapshot))
                            exporting = true
                        } catch { family.issue = familyErrorText(error) }
                    }.disabled(family.busy)
                    Button(L("Открыть общую после сохранения копии")) {
                        Task { await family.join(mergeLocal: false, exportedSnapshot: exportedSnapshot) }
                    }.disabled(exportedSnapshot != store.snapshot || family.busy)
                } footer: {
                    Text(L("Переключение станет доступно после успешного сохранения резервной копии. При праве только на чтение добавлять свои книги в общую библиотеку нельзя."))
                }.archiveRow()
                if family.busy { Section { ProgressView(L("Синхронизация…")) }.archiveRow() }
                if let issue = family.issue { Section { Text(issue).foregroundStyle(.red) }.archiveRow() }
            }.archiveScreen().navigationTitle(L("Семейный доступ")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) {
                        Button(L("Отмена")) { family.invitation = nil }.disabled(family.busy)
                    }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Bookreign-before-family") { result in
                    switch result {
                    case .success: exportedSnapshot = exportingSnapshot
                    case .failure(let error): family.issue = familyErrorText(error)
                    }
                }
        }.interactiveDismissDisabled(family.busy)
    }
}
