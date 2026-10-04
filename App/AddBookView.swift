import SwiftUI
import PhotosUI
import LibraryCore
import BookCatalog
import ImageIO

struct AddBookView: View {
    var initialLocation: UUID? = nil
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchLanguage = "all"
    @State private var results: [CatalogBook] = []
    @State private var catalogAlternatives: [CatalogBook] = []
    @State private var selectedCatalogID = ""
    @State private var loading = false
    @State private var activeSearchQuery: String?
    @State private var notice: LocalizedMessage?
    @State private var draft = BookEdition(title: "")
    @State private var editing = false
    @State private var location: UUID?
    @State private var shelf = ""
    @State private var scanning = true
    @State private var compactConfirmation = false
    @State private var showDetails = false
    @State private var reviewingBatch = false
    @State private var scanLookup = false
    @State private var scanner = false
    @State private var scannedISBNToReview: String?
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var recognizedText = ""
    @State private var recognitionInfo: LocalizedMessage?
    @State private var recognitionBusy = false
    @State private var photoTask: Task<Void, Never>?
    @State private var photoRequestID = UUID()
    @State private var coverLoading = false
    @State private var duplicate: BookEdition?
    @State private var showDuplicate = false
    @State private var saved = false
    @State private var queuedISBN: String?
    @State private var remainingCount = ScanQueueStore.codes.count
    @State private var searchTask: Task<Void, Never>?
    @State private var requestID = UUID()
    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && location != nil && !recognitionBusy && !coverLoading && !saved
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if scanning {
                    SingleBookScannerView(locationName: location.map(store.locationName) ?? L("Выберите место"),
                                          onISBN: searchScannedISBN,
                                          onOtherMethods: { scanning = false },
                                          onBatch: { scanning = false; scanner = true })
                } else if scanLookup && loading {
                    VStack(spacing: 20) {
                        ProgressView(L("Ищу книгу по ISBN…"))
                        Text(ISBNInputFormatting.format(query)).font(.system(.body, design: .monospaced))
                        Button(L("Вернуться к сканеру")) { returnToScanner() }
                            .buttonStyle(ArchiveSecondaryButtonStyle())
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.paper)
                } else {
                    if compactConfirmation {
                        ArchivePageHeader(title: L("Книга найдена"))
                    }
                    ScrollViewReader { scroll in
                        bookForm
                            // Entering a new card starts with its title, even when
                            // the catalog fallback was near the bottom of the form.
                            .id(editing)
                            .onChange(of: showDetails) { _, showing in
                                if showing {
                                    withAnimation { scroll.scrollTo("editingMetadata", anchor: .top) }
                                }
                            }
                    }
                }
            }
            .archiveScreen()
            .navigationTitle(editing ? L("Проверить книгу") : (scanning ? L("Сканирование") : L("Добавить книгу")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ArchiveToolbarItem(placement: .cancellationAction) {
                    Button(editing ? L("Назад") : L("Отмена")) {
                        if editing {
                            if compactConfirmation { returnToScanner() } else { returnToStart() }
                        } else { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editing {
                    VStack(spacing: 4) {
                        Button { attemptSave() } label: {
                            Text(compactConfirmation ? L("Подтвердить") : L("Добавить в библиотеку"))
                                .font(.headline).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("confirmBook")
                        .buttonStyle(ArchivePrimaryButtonStyle()).disabled(!canSave)
                        if compactConfirmation {
                            Button { showDetails.toggle() } label: {
                                Label(showDetails ? L("Скрыть данные книги") : L("Изменить данные книги"), systemImage: "square.and.pencil")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.forest)
                            .accessibilityIdentifier("editBookDetails")
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, compactConfirmation ? 4 : 12)
                    .background(Color.paper.ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) { Rectangle().fill(Color.archiveRule).frame(height: 1) }
                }
            }
            .onAppear { if location == nil { location = initialLocation ?? store.snapshot.locations.first?.id }; remainingCount = ScanQueueStore.codes.count }
            .onDisappear {
                cancelSearch()
                if !camera && !scanner { cancelPhotoRecognition() }
            }
            .onChange(of: query) { _, value in
                let current = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let activeSearchQuery, current != activeSearchQuery { cancelSearch() }
                if let queuedISBN, ISBN.canonical(value) != ISBN.canonical(queuedISBN) {
                    self.queuedISBN = nil
                }
            }
            .onChange(of: searchLanguage) { _, _ in cancelSearch() }
            .onChange(of: photo) { _, value in
                guard let value else { return }
                loadPickedPhoto(value)
            }
            .sheet(isPresented: $scanner, onDismiss: {
                remainingCount = ScanQueueStore.codes.count
                if let isbn = scannedISBNToReview {
                    scannedISBNToReview = nil
                    continueQueue(startingWith: isbn)
                }
            }) {
                BarcodeBatchView(locationName: location.map(store.locationName) ?? L("Выберите место"), onReview: {
                    scannedISBNToReview = ScanQueueStore.codes.first
                    scanner = false
                }, onSearch: { isbn in
                    scannedISBNToReview = isbn
                    scanner = false
                })
            }
            .fullScreenCover(isPresented: $camera) {
                BookCameraPicker(onImage: { data in camera = false; beginPhotoRecognition(data) }, onCancel: { camera = false }).ignoresSafeArea()
            }
            .confirmationDialog(L("Это издание уже есть"), isPresented: $showDuplicate, titleVisibility: .visible) {
                if let duplicate {
                    Button(L("Добавить ещё один экземпляр")) { save(existingID: duplicate.id) }
                    Button(L("Сохранить как отдельное издание")) { save(existingID: nil) }
                }
                Button(L("Отмена"), role: .cancel) {}
            } message: {
                if let duplicate {
                    Text(L("\(displayBookTitle(duplicate))\n\(store.copies(for: duplicate.id).map { store.locationName($0.locationID) }.joined(separator: ", ")). При добавлении экземпляра сохранится существующая карточка издания."))
                }
            }
        }
    }
    private var bookForm: some View {
        let fromPhotosTitle = L("Из фото")
        return Form {
                if editing {
                    if compactConfirmation {
                        Section {
                            VStack(spacing: 12) {
                                BookCover(edition: draft, large: true).frame(width: 156, height: 230)
                                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityHidden(false)
                                    .accessibilityLabel(L("Обложка книги"))
                                    .accessibilityIdentifier("confirmationCover")
                                if draft.coverData == nil && draft.coverURL.isEmpty {
                                    Text(L("Обложка не выбрана")).font(.caption).foregroundStyle(Color.archiveSecondary)
                                }
                                Text(displayBookTitle(draft)).font(.system(.title2, design: .serif, weight: .medium))
                                    .multilineTextAlignment(.center).accessibilityIdentifier("confirmationBookTitle")
                                if !draft.author.isEmpty { Text(draft.author).foregroundStyle(Color.archiveSecondary).multilineTextAlignment(.center) }
                                if !draft.isbn.isEmpty {
                                    Text("ISBN \(ISBNInputFormatting.format(draft.isbn))")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Color.archiveSecondary)
                                        .textSelection(.enabled)
                                }
                                Text(languageName(draft.language)).font(.caption).foregroundStyle(Color.forest)
                                Label(location.map(store.locationName) ?? L("Выберите место"), systemImage: "mappin.and.ellipse")
                                    .font(.caption).foregroundStyle(Color.archiveSecondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    if catalogAlternatives.count > 1 {
                        Section {
                            Picker(L("Данные книги"), selection: Binding(get: { selectedCatalogID }, set: { id in
                                guard let item = catalogAlternatives.first(where: { $0.id == id }) else { return }
                                let originalGenres = catalogAlternatives.first(where: { $0.id == selectedCatalogID }).map { BookEdition.normalizedGenres($0.genres) } ?? []
                                selectedCatalogID = id
                                var replacement = fromCatalog(item)
                                replacement.notes = draft.notes
                                replacement.coverData = draft.coverData
                                if draft.coverData != nil { replacement.coverURL = draft.coverURL }
                                if draft.genres != originalGenres { replacement.genres = draft.genres }
                                draft = replacement
                            })) {
                                ForEach(catalogAlternatives) { item in
                                    Text("\(languageName(item.language)) · \(item.title)").tag(item.id)
                                }
                            }.accessibilityIdentifier("catalogEditionVariant")
                        } footer: {
                            Text(L("Для одного ISBN каталоги могут предлагать разные сведения. По умолчанию предпочитаем украинскую карточку; проверьте язык вашей книги."))
                        }.archiveRow()
                    }
                    if !compactConfirmation { EditionFields(edition: $draft) }
                    CoverEditor(edition: $draft, isLoading: $coverLoading)
                    LocationFields(location: $location, shelf: $shelf)
                    if compactConfirmation && showDetails {
                        EditionFields(edition: $draft).id("editingMetadata")
                    }
                    if queuedISBN != nil {
                        Section { Button(L("Пропустить — оставить в очереди")) { returnToStart() } }.archiveRow()
                    }
                } else {
                    Section {
                        Button { returnToScanner() } label: { Label(L("Сканировать штрихкод"), systemImage: "barcode.viewfinder").font(.headline).padding(.vertical, 7) }.disabled(recognitionBusy)
                        HStack {
                            Button { camera = true } label: { Label(L("Фото обложки"), systemImage: "camera") }.buttonStyle(.borderless).disabled(recognitionBusy)
                            Spacer()
                            PhotosPicker(selection: $photo, matching: .images) { Label(fromPhotosTitle, systemImage: "photo") }.buttonStyle(.borderless).disabled(recognitionBusy)
                        }.padding(.vertical, 5)
                        Button(L("Ввести вручную"), systemImage: "square.and.pencil") { beginEditing(BookEdition(title: "", coverData: coverData)) }.padding(.vertical, 5).disabled(recognitionBusy)
                    } footer: { Text(L("ISBN точнее определяет издание. Обложка помогает найти название и автора.")) }.archiveRow()
                    if remainingCount > 0 {
                        Section {
                            Button { continueQueue() } label: { Label(L("Продолжить очередь: \(remainingCount)"), systemImage: "tray.full") }.disabled(recognitionBusy)
                        } footer: { Text(L("Отсканированные ISBN сохраняются на устройстве, даже если нет интернета.")) }.archiveRow()
                    }
                    LocationFields(location: $location, shelf: $shelf)
                    if recognitionBusy {
                        Section { ProgressView(L("Читаю текст обложки…")) }.archiveRow()
                    }
                    if !recognizedText.isEmpty {
                        Section {
                            TextEditor(text: $recognizedText).frame(minHeight: 90).scrollContentBackground(.hidden)
                            Button(L("Искать по этому тексту"), systemImage: "magnifyingglass") { query = recognizedText.replacingOccurrences(of: "\n", with: " "); search() }.disabled(recognitionBusy)
                            Button(L("Использовать как название")) { beginEditing(BookEdition(title: recognizedText, coverData: coverData)) }.disabled(recognitionBusy)
                        } header: { Text(L("Текст с обложки — можно исправить")) } footer: { Text(L(recognitionInfo ?? "")) }.archiveRow()
                    } else if let recognitionInfo {
                        Section { Text(L(recognitionInfo)).font(.caption).foregroundStyle(Color.archiveSecondary) }.archiveRow()
                    }
                    Section {
                        TextField(L("Название, автор или ISBN"), text: $query).autocorrectionDisabled().submitLabel(.search).onSubmit { search() }.disabled(recognitionBusy).accessibilityIdentifier("catalogQuery")
                        Picker(L("Язык результатов"), selection: $searchLanguage) {
                            Text(L("Все языки")).tag("all")
                            ForEach(["uk", "ru", "en"], id: \.self) { Text(languageName($0)).tag($0) }
                        }
                        Button { search() } label: { HStack { Label(L("Найти книгу"), systemImage: "magnifyingglass"); if loading { Spacer(); ProgressView() } } }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading || recognitionBusy)
                    } header: { Text(L("Поиск в каталоге")) } footer: { Text(L("Поиск использует внешние книжные каталоги. Если книга не найдена, её можно добавить вручную.")) }.archiveRow()
                    if let notice {
                        Section {
                            Text(L(notice)).font(.subheadline).foregroundStyle(Color.archiveSecondary)
                            Button(L("Заполнить самостоятельно")) { beginEditing(BookEdition(title: ISBN.normalize(query) == nil ? query : "", isbn: ISBN.normalize(query) ?? "", coverData: coverData)) }.disabled(recognitionBusy)
                            if let isbn = ISBN.normalize(query) {
                                Button(L("Сохранить ISBN, заполнить позже")) { beginEditing(BookEdition(title: "Книга · \(isbn)", isbn: isbn, coverData: coverData, notes: "Данные издания нужно заполнить.")) }.disabled(recognitionBusy)
                            }
                        }.archiveRow()
                    }
                    if !results.isEmpty {
                        Section(L("Выберите своё издание")) {
                            ForEach(results) { result in
                                Button { select(result, alternatives: results) } label: {
                                    HStack(spacing: 13) {
                                        BookCover(edition: fromCatalog(result)).frame(width: 43, height: 64)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(result.title).font(.system(.headline, design: .serif)).foregroundStyle(Color.archiveText)
                                            Text(result.author).font(.subheadline).foregroundStyle(Color.archiveSecondary)
                                            Text([languageName(result.language), result.publisher, result.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.archiveSecondary)
                                            if !result.sourceName.isEmpty { Text(catalogSourceDisplayName(result.sourceName)).font(.caption2).foregroundStyle(Color.archiveSecondary) }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }.disabled(recognitionBusy)
                            }
                        }.archiveRow()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
    }
    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        requestID = UUID()
        activeSearchQuery = nil
        results = []
        loading = false
        notice = nil
        scanLookup = false
    }
    private func returnToScanner() {
        returnToStart()
        scanning = true
    }
    private func searchScannedISBN(_ isbn: String) {
        guard scanning else { return }
        scanning = false
        ScanQueueStore.append(isbn)
        continueQueue(startingWith: isbn, batch: false)
    }
    private func returnToStart() {
        cancelSearch()
        cancelPhotoRecognition()
        queuedISBN = nil
        editing = false
        compactConfirmation = false
        showDetails = false
        reviewingBatch = false
        coverData = nil
        recognizedText = ""
        recognitionInfo = nil
        query = ""
        remainingCount = ScanQueueStore.codes.count
    }
    private func beginEditing(_ edition: BookEdition) {
        cancelSearch()
        cancelPhotoRecognition()
        catalogAlternatives = []
        selectedCatalogID = ""
        draft = edition
        scanning = false
        compactConfirmation = false
        showDetails = false
        saved = false
        editing = true
    }
    private func continueQueue(startingWith preferredISBN: String? = nil, batch: Bool = true) {
        guard let isbn = preferredISBN ?? ScanQueueStore.codes.first else { queuedISBN = nil; remainingCount = 0; return }
        cancelSearch()
        scanning = false
        reviewingBatch = batch
        editing = false; queuedISBN = isbn; query = isbn; remainingCount = ScanQueueStore.codes.count
        search()
        scanLookup = true
    }
    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !recognitionBusy, !editing else { return }
        searchTask?.cancel()
        let token = UUID(); requestID = token
        activeSearchQuery = term
        loading = true; results = []; notice = nil
        let lang = searchLanguage == "all" ? nil : searchLanguage
        searchTask = Task {
            do {
                let found: [CatalogBook]
                if let isbn = ISBN.normalize(term) { found = try await CatalogService.client().lookup(isbn: isbn, preferredLanguage: lang ?? "uk") }
                else { found = try await CatalogService.client().search(term, language: lang) }
                guard !Task.isCancelled, token == requestID, !editing, query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
                results = found; loading = false
                if found.isEmpty { notice = "Точного совпадения в подключённых каталогах нет. Можно заполнить карточку вручную или сохранить ISBN и повторить поиск позже." }
                else if ISBN.normalize(term) != nil, let preferred = found.first { select(preferred, alternatives: found) }
            } catch {
                guard !Task.isCancelled, token == requestID, !editing, query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
                loading = false; notice = "Поиск недоступен: \(L10n.error(error)) Вы можете добавить книгу вручную или вернуться к очереди позже."
            }
        }
    }
    private func fromCatalog(_ item: CatalogBook) -> BookEdition {
        BookEdition(title: item.title, author: item.author, isbn: item.isbn, language: item.language, publisher: item.publisher, year: item.year, coverURL: item.coverURL, coverData: coverData, genres: item.genres)
    }
    private func select(_ item: CatalogBook, alternatives: [CatalogBook] = []) {
        let isISBNLookup = ISBN.normalize(query) != nil
        beginEditing(fromCatalog(item))
        compactConfirmation = isISBNLookup
        if let isbn = ISBN.canonical(item.isbn) {
            catalogAlternatives = alternatives.filter { ISBN.canonical($0.isbn) == isbn }
        }
        selectedCatalogID = item.id
    }
    private func attemptSave() {
        guard canSave else { return }
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let isbn = ISBN.normalize(draft.isbn) {
            draft.isbn = isbn
            let canonical = ISBN.canonical(isbn)
            duplicate = store.snapshot.editions.first { ISBN.canonical($0.isbn) == canonical }
        } else { duplicate = nil }
        if duplicate != nil { showDuplicate = true } else { save(existingID: nil) }
    }
    private func save(existingID: UUID?) {
        guard canSave else { return }
        let completedQueueCode = QueueCompletion.completedCode(savedISBN: draft.isbn, queuedISBN: queuedISBN)
        guard let location, store.add(draft, location: location, shelf: shelf, existingID: existingID) else { return }
        saved = true
        if let completedQueueCode {
            ScanQueueStore.remove(completedQueueCode)
            self.queuedISBN = nil
            coverData = nil; recognizedText = ""; recognitionInfo = nil
            if reviewingBatch && !ScanQueueStore.codes.isEmpty { continueQueue() } else { dismiss() }
        } else { dismiss() }
    }
    private func cancelPhotoRecognition() {
        photoTask?.cancel()
        photoTask = nil
        photoRequestID = UUID()
        recognitionBusy = false
        photo = nil
    }
    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        cancelSearch()
        photoTask?.cancel()
        let token = UUID()
        photoRequestID = token
        recognitionBusy = true
        recognizedText = ""
        recognitionInfo = nil
        photoTask = Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                guard !Task.isCancelled, token == photoRequestID else { return }
                await recognize(data, token: token)
            } catch {
                guard !Task.isCancelled, token == photoRequestID else { return }
                notice = "Не удалось открыть фотографию: \(L10n.error(error))"
                recognitionBusy = false
            }
            if token == photoRequestID { photo = nil; photoTask = nil }
        }
    }
    private func beginPhotoRecognition(_ data: Data) {
        cancelSearch()
        photoTask?.cancel()
        let token = UUID()
        photoRequestID = token
        recognitionBusy = true
        recognizedText = ""
        recognitionInfo = nil
        photoTask = Task { await recognize(data, token: token) }
    }
    @MainActor private func recognize(_ data: Data, token: UUID) async {
        guard !Task.isCancelled, token == photoRequestID, !editing else { return }
        guard let compressed = compactPhoto(data) else {
            guard token == photoRequestID else { return }
            recognitionBusy = false
            notice = "Не удалось прочитать изображение."
            return
        }
        guard !Task.isCancelled, token == photoRequestID, !editing else { return }
        coverData = compressed
        do {
            let recognition = try await CoverTextRecognizer.recognize(compressed)
            guard !Task.isCancelled, token == photoRequestID, !editing else { return }
            recognizedText = recognition.text
            let supported = recognition.supportedBookLanguages.map(languageName).joined(separator: ", ")
            recognitionInfo = supported.isEmpty
                ? "Vision не сообщил о поддержке этих языков OCR на устройстве. Проверьте распознанный текст. Фото не отправляется в интернет."
                : "На этом устройстве OCR поддерживает: \(supported). Проверьте распознанный текст. Фото не отправляется в интернет."
            if recognition.text.isEmpty { recognitionInfo = "Текст не распознан. Снимите обложку ближе при хорошем свете или введите название вручную. Фото можно сохранить как обложку." }
            if let isbn = ISBN.extract(from: recognition.text).first { query = isbn }
        } catch {
            guard !Task.isCancelled, token == photoRequestID else { return }
            recognitionInfo = "Не удалось распознать текст. Введите название вручную. Фото сохранено для карточки."
        }
        if token == photoRequestID { recognitionBusy = false; photoTask = nil }
    }
}

@MainActor
func compactPhoto(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
    return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
}

enum ScanQueueStore {
    static var codes: [String] { UserDefaults.standard.stringArray(forKey: "pendingISBNs") ?? [] }
    static func append(_ code: String) { var values = codes; if !values.contains(code) { values.append(code); UserDefaults.standard.set(values, forKey: "pendingISBNs") } }
    static func remove(_ code: String) { UserDefaults.standard.set(codes.filter { $0 != code }, forKey: "pendingISBNs") }
}

/// An ISBN leaves the scan queue only when that exact edition was saved.
enum QueueCompletion {
    static func completedCode(savedISBN: String, queuedISBN: String?) -> String? {
        guard let queuedISBN,
              let saved = ISBN.canonical(savedISBN),
              let queued = ISBN.canonical(queuedISBN),
              saved == queued else { return nil }
        return queuedISBN
    }
}

struct BarcodeBatchView: View {
    let locationName: String
    var onReview: () -> Void
    var onSearch: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var codes = ScanQueueStore.codes
    @State private var manualISBN = ""
    @State private var feedback: LocalizedMessage?
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                BarcodeScannerView { raw in add(raw) }
                    .frame(height: min(275, max(90, geometry.size.height * 0.32))).clipped()
                HStack { Label(locationName, systemImage: "mappin.and.ellipse"); Spacer(); Text(L("В очереди: \(codes.count)")) }.font(.subheadline.weight(.medium)).padding().foregroundStyle(Color.archiveText).background(Color.archiveSurface)
                List {
                    Section {
                        HStack {
                            ISBNInputField(text: $manualISBN, accessibilityLabel: L("Ввести ISBN"), accessibilityIdentifier: "scannerISBN", onSubmit: searchManualISBN)
                            Button { if add(manualISBN) != nil { manualISBN = "" } } label: {
                                Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel(L("Добавить ISBN в очередь"))
                        }
                        if let feedback { Text(L(feedback)).font(.caption).foregroundStyle(Color.archiveSecondary) }
                    } footer: { Text(L("Введите ISBN и нажмите «Найти» на клавиатуре для поиска. Кнопка «+» добавляет код в очередь. Очередь сохранится, даже если закрыть экран.")) }.archiveRow()
                    Section(L("Отсканировано")) {
                        ForEach(codes, id: \.self) { code in Label(code, systemImage: "barcode").font(.system(.body, design: .monospaced)) }
                            .onDelete { indices in let remove = indices.map { codes[$0] }; remove.forEach(ScanQueueStore.remove); codes = ScanQueueStore.codes }
                    }.archiveRow()
                }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden)
                Button { onReview() } label: { Text(L("Проверить и добавить (\(codes.count))")).font(.headline).frame(maxWidth: .infinity).padding(7) }.buttonStyle(ArchivePrimaryButtonStyle()).disabled(codes.isEmpty).padding()
                }
            }.archiveScreen().navigationTitle(L("Сканирование")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Готово")) { dismiss() } } }
        }
    }
    private func searchManualISBN() {
        guard let isbn = add(manualISBN) else { return }
        manualISBN = ""
        onSearch(isbn)
    }
    @discardableResult private func add(_ raw: String) -> String? {
        guard let isbn = ISBN.normalize(raw) else { feedback = "Это не ISBN книги. Нужен код ISBN-10 или ISBN-13 с верной контрольной цифрой."; return nil }
        if codes.contains(isbn) { feedback = "Этот ISBN уже в очереди. Дополнительный экземпляр можно добавить в карточке книги."; return isbn }
        ScanQueueStore.append(isbn); codes = ScanQueueStore.codes; feedback = "Добавлен ISBN \(isbn)"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return isbn
    }
}
