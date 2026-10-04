import SwiftUI
import UniformTypeIdentifiers
import LibraryCore

struct LibraryFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = AppPreferences.shared
    @State private var exporting = false
    @State private var importing = false
    @State private var document = LibraryFile(data: Data())
    @State private var contentType = UTType.json
    @State private var filename = "Bookreign-backup"
    @State private var pendingImport: Data?
    @State private var importedEditionCount = 0
    @State private var importedCopyCount = 0
    @State private var confirmRestore = false
    @State private var message: String?

    var body: some View {
        @Bindable var preferences = preferences
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "books.vertical.fill").font(.largeTitle).foregroundStyle(Color.forest)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Bookreign")).font(.system(.title2, design: .serif, weight: .semibold))
                            Text(L("Ваши книги. На своих местах.")).font(.subheadline).foregroundStyle(Color.archiveSecondary)
                            Text(L("Версия \(AppVersion.displayString)"))
                                .font(.caption).foregroundStyle(Color.archiveSecondary)
                                .accessibilityIdentifier("appVersion")
                        }
                    }.padding(.vertical, 10)
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label(L("Политика конфиденциальности"), systemImage: "hand.raised")
                    }.accessibilityIdentifier("privacyPolicyLink")
                }.archiveRow()
                Section {
                    Picker(L("Тема"), selection: $preferences.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                                .accessibilityIdentifier("theme-\(appearance.rawValue)")
                        }
                    }.accessibilityIdentifier("appearancePicker")
                } header: { Text(L("Оформление")) } footer: {
                    Text(L("Светлая — «Зелёный переплёт». Тёмная — «Ночной архив»."))
                }.archiveRow()
                Section(L("Язык интерфейса")) {
                    Picker(L("Язык"), selection: $preferences.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                                .accessibilityIdentifier("language-\(language.rawValue)")
                        }
                    }.accessibilityIdentifier("interfaceLanguagePicker")
                }.archiveRow()
                Section {
                    Button(L("Сохранить резервную копию"), systemImage: "externaldrive.badge.plus") { exportBackup() }
                    Button(L("Экспортировать в CSV"), systemImage: "tablecells") {
                        document = LibraryFile(data: Data(LibraryBackup.csv(store.snapshot).utf8)); filename = "Bookreign-library"; contentType = .commaSeparatedText; exporting = true
                    }
                    Button(L("Восстановить из копии"), systemImage: "arrow.clockwise.icloud") { importing = true }
                } header: { Text(L("Ваши данные")) } footer: { Text(L("Библиотека хранится на этом устройстве. JSON-копия содержит книги, фотографии, места и историю выдачи. CSV подходит для таблиц; восстановление из CSV пока не поддерживается.")) }
                    .archiveRow()
                Section {
                    LabeledContent(L("Издания"), value: "\(store.snapshot.editions.count)")
                    LabeledContent(L("Экземпляры"), value: "\(store.snapshot.copies.count)")
                    LabeledContent(L("На руках"), value: "\(store.activeLoans.count)")
                    if store.canUndo { Button(L("Отменить последнее изменение"), systemImage: "arrow.uturn.backward") { store.undo() } }
                }.archiveRow()
            }.archiveScreen().navigationTitle(L("Настройки")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ArchiveToolbarItem(placement: .confirmationAction) {
                        Button(L("Готово")) { dismiss() }.accessibilityIdentifier("settingsDone")
                    }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: filename) { result in
                    if case .failure(let error) = result { message = L10n.error(error) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let state = try LibraryBackup.decode(data)
                        pendingImport = data
                        importedEditionCount = state.editions.count
                        importedCopyCount = state.copies.count
                        confirmRestore = true
                    } catch { message = L("Не удалось прочитать копию: \(L10n.error(error))") }
                }
                .confirmationDialog(L("Заменить библиотеку?"), isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button(L("Восстановить и заменить"), role: .destructive) {
                        guard let data = pendingImport else { return }
                        do { if try store.restore(data) { message = L("Библиотека восстановлена.") } } catch { message = L10n.error(error) }
                        pendingImport = nil
                    }
                    Button(L("Отмена"), role: .cancel) { pendingImport = nil }
                } message: {
                    Text(L("В копии изданий: \(importedEditionCount), экземпляров: \(importedCopyCount). Текущая библиотека будет заменена. Сначала сохраните её резервную копию. Последнее изменение можно отменить до закрытия приложения."))
                }
                .alert(L("Резервная копия"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button(L("Понятно"), role: .cancel) {} } message: { Text(message ?? "") }
        }
    }

    private func exportBackup() {
        do { document = LibraryFile(data: try LibraryBackup.encode(store.snapshot)); filename = "Bookreign-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"; contentType = .json; exporting = true }
        catch { message = L10n.error(error) }
    }
}
