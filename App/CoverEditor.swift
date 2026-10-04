import SwiftUI
import PhotosUI
import UIKit
import LibraryCore
import BookCatalog

/// A compact entry point shared by the add and edit forms.
struct CoverEditor: View {
    @Binding var edition: BookEdition
    @Binding var isLoading: Bool
    @State private var presentedEdition: BookEdition?

    init(edition: Binding<BookEdition>, isLoading: Binding<Bool> = .constant(false)) {
        _edition = edition
        _isLoading = isLoading
    }

    var body: some View {
        Section(L("Обложка")) {
            Button {
                presentedEdition = edition
            } label: {
                Label(edition.coverData == nil && edition.coverURL.isEmpty ? L("Добавить обложку") : L("Изменить обложку"), systemImage: "photo.badge.plus")
            }
            .accessibilityIdentifier("coverEditorButton")
            // Form flattens Section into its rows; attach presentation to the
            // actual row so it has a stable presenting view controller.
            .sheet(item: $presentedEdition, onDismiss: { isLoading = false }) { original in
                CoverPickerSheet(edition: original) { data, sourceURL in
                    guard edition.id == original.id else { return }
                    edition.coverData = data
                    edition.coverURL = sourceURL
                }
            }
            .onChange(of: edition.id) { _, _ in presentedEdition = nil }
        }.archiveRow()
    }
}

/// Does not mutate a book until the user confirms a successfully decoded cover.
/// Callers can persist just these two fields without replacing the book's metadata.
struct CoverPickerSheet: View {
    let onSelect: (Data, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: CoverSelectionModel
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var photo: PhotosPickerItem?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case query, url }

    init(edition: BookEdition, onSelect: @escaping (Data, String) -> Void) {
        self.onSelect = onSelect
        _model = State(initialValue: CoverSelectionModel(edition: edition))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List {
                    preview.id("coverPreview")
                    if let error = model.importError {
                        Section {
                            Text(L(error)).font(.subheadline).foregroundStyle(.red)
                                .accessibilityIdentifier("coverSourceError")
                        }.archiveRow()
                    }
                    photoSources
                    catalogSearch
                    internetSources
                }
                .scrollContentBackground(.hidden)
                .background(Color.paper)
                .onChange(of: model.selectedData != nil) { _, ready in
                    if ready { withAnimation { scroll.scrollTo("coverPreview", anchor: .top) } }
                }
                .onChange(of: model.importError) { _, error in
                    if error != nil { withAnimation { scroll.scrollTo("coverPreview", anchor: .top) } }
                }
            }
            .archiveScreen()
            .navigationTitle(L("Выбрать обложку"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ArchiveToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена")) { model.cancel(); dismiss() }
                        .accessibilityIdentifier("coverCancelButton")
                }
                ArchiveToolbarItem(placement: .confirmationAction) {
                    Button(L("Использовать обложку")) {
                        guard let data = model.selectedData, !model.isImporting else { return }
                        onSelect(data, model.selectedURL)
                        model.cancel()
                        dismiss()
                    }
                    .disabled(model.selectedData == nil || model.isImporting)
                    .accessibilityIdentifier("coverConfirmButton")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .onAppear { model.start() }
        .onDisappear {
            // Camera and Photos are child presentations, not cancellation of this editor.
            if !showingCamera && !showingPhotos { model.cancel() }
        }
        .sheet(isPresented: $showingCamera) {
            BookCameraPicker { data in
                model.importPhoto(data)
                showingCamera = false
            } onCancel: { showingCamera = false }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            model.importPhoto(item)
            photo = nil
        }
    }

    private var preview: some View {
        Section {
            VStack(spacing: 10) {
                BookCover(edition: model.previewEdition, large: true)
                    .frame(width: 142, height: 209)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
                Text(displayBookTitle(model.original))
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .multilineTextAlignment(.center)
                if model.isImporting {
                    ProgressView(L("Загружаю обложку…"))
                } else if model.selectedData != nil {
                    Label(L("Обложка готова"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Color.forest)
                        .accessibilityIdentifier("coverPreviewStatus")
                    if !model.selectedTitle.isEmpty {
                        Text(model.selectedTitle).font(.caption).foregroundStyle(Color.archiveSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
        } footer: {
            Text(L("Выберите подходящее издание по обложке. Название, автор и язык вашей книги сохранятся."))
        }.archiveRow()
    }

    private var photoSources: some View {
        Section {
            Button(L("Сфотографировать обложку"), systemImage: "camera") {
                focusedField = nil
                showingCamera = true
            }.accessibilityIdentifier("coverCameraButton")
            Button(L("Выбрать фото обложки"), systemImage: "photo.on.rectangle") {
                focusedField = nil
                showingPhotos = true
            }.accessibilityIdentifier("coverPhotosButton")
        }.archiveRow().disabled(model.isImporting)
    }

    private var catalogSearch: some View {
        Section {
            HStack {
                TextField(L("Название, автор или ISBN"), text: $model.query)
                    .focused($focusedField, equals: .query)
                    .submitLabel(.search)
                    .onSubmit(search)
                    .accessibilityIdentifier("coverSearchQuery")
                Button(action: search) {
                    Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(L("Найти обложки"))
                    .accessibilityIdentifier("coverSearchButton")
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.isSearching { ProgressView(L("Ищу обложки…")) }
            if let error = model.searchError {
                Text(L(error)).font(.subheadline).foregroundStyle(Color.archiveSecondary)
                Button(L("Повторить поиск"), action: search)
            } else if model.searched && !model.isSearching && model.candidates.isEmpty {
                Text(L("Обложки не найдены. Измените запрос, откройте поиск в интернете или добавьте фото."))
                    .font(.subheadline).foregroundStyle(Color.archiveSecondary)
            }
            ForEach(model.candidates) { candidate in
                Button { focusedField = nil; model.select(candidate) } label: {
                    HStack(spacing: 12) {
                        CoverCandidateThumbnail(book: candidate)
                            .frame(width: 43, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.title).font(.system(.subheadline, design: .serif, weight: .medium)).foregroundStyle(Color.archiveText)
                            if !candidate.author.isEmpty { Text(candidate.author).font(.caption).foregroundStyle(Color.archiveSecondary) }
                            Text(catalogSourceDisplayName(candidate.sourceName.isEmpty ? "Open Library" : candidate.sourceName))
                                .font(.caption2).foregroundStyle(Color.archiveSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: model.selectedURL == candidate.coverURL ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(Color.forest)
                    }.padding(.vertical, 3)
                }
                .accessibilityIdentifier("coverCandidate-\(candidate.id)")
            }
        } header: { Text(L("Обложки из каталогов")) }.archiveRow()
    }

    private var internetSources: some View {
        Section {
            if let url = CoverSearch.webSearchURL(query: model.query) {
                Link(destination: url) { Label(L("Поиск картинок в интернете"), systemImage: "safari") }
                    .accessibilityIdentifier("coverWebSearchButton")
            }
            TextField(L("Прямая ссылка на изображение (HTTPS)"), text: $model.imageURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focusedField, equals: .url).submitLabel(.go)
                .onSubmit(importURL)
                .accessibilityIdentifier("coverURLField")
            Button(L("Загрузить по ссылке"), systemImage: "arrow.down.circle", action: importURL)
                .disabled(model.imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isImporting)
                .accessibilityIdentifier("coverURLLoadButton")
        } footer: {
            Text(L("Вставьте ссылку на саму картинку, а не на страницу сайта. Или сохраните найденную обложку в Фото и выберите её здесь."))
        }.archiveRow()
    }

    private func search() { focusedField = nil; model.search() }
    private func importURL() { focusedField = nil; model.importURL() }
}

private struct CoverCandidateThumbnail: View {
    let book: CatalogBook
    var body: some View {
        Group {
            if CoverTestFixture.enabled, let data = CoverTestFixture.image(for: book.coverURL), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if CoverTestFixture.enabled {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                AsyncImage(url: CoverSearch.imageURL(book.coverURL)) { image in
                    image.resizable().scaledToFit()
                } placeholder: { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }.accessibilityHidden(true)
    }
}

@MainActor
@Observable
private final class CoverSelectionModel {
    let original: BookEdition
    var query: String
    var imageURL = ""
    var candidates: [CatalogBook] = []
    var isSearching = false
    var searched = false
    var searchError: LocalizedMessage?
    var importError: LocalizedMessage?
    var isImporting = false
    var selectedData: Data?
    var selectedURL = ""
    var selectedTitle = ""
    private var started = false
    private var searchRequest = UUID()
    private var importRequest = UUID()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init(edition: BookEdition) {
        original = edition
        let title = edition.hasPlaceholderTitle ? "" : edition.title.trimmingCharacters(in: .whitespacesAndNewlines)
        query = title.isEmpty ? edition.isbn : [title, edition.author].filter { !$0.isEmpty }.joined(separator: " ")
    }

    deinit { searchTask?.cancel(); importTask?.cancel() }

    var previewEdition: BookEdition {
        var edition = original
        if let selectedData { edition.coverData = selectedData; edition.coverURL = selectedURL }
        return edition
    }

    func start() {
        guard !started else { return }
        started = true
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { search() }
    }

    func search() {
        searchTask?.cancel()
        let token = UUID()
        searchRequest = token
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        candidates = []
        searchError = nil
        searched = !query.isEmpty
        guard !query.isEmpty else { isSearching = false; return }
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                let books: [CatalogBook]
                if CoverTestFixture.enabled {
                    books = CoverTestFixture.books
                } else if ISBN.normalize(query) != nil {
                    books = try await CatalogService.client().lookup(isbn: query)
                } else {
                    books = try await CatalogService.client().search(query)
                }
                try Task.checkCancellation()
                guard let self, token == self.searchRequest else { return }
                self.candidates = CoverSearch.candidates(from: books)
                self.isSearching = false
                self.searchTask = nil
            } catch {
                guard let self, !Task.isCancelled, token == self.searchRequest else { return }
                self.searchError = "Не удалось найти обложки. Проверьте подключение и повторите поиск."
                self.isSearching = false
                self.searchTask = nil
            }
        }
    }

    func select(_ book: CatalogBook) {
        guard let url = CoverSearch.imageURL(book.coverURL) else { importError = "Нужна прямая HTTPS-ссылка на изображение."; return }
        beginImport(sourceURL: url.absoluteString, title: book.title) { try await CoverImageLoader.load(url) }
    }

    func importURL() {
        guard let url = CoverSearch.imageURL(imageURL) else { importError = "Нужна прямая HTTPS-ссылка на изображение."; return }
        beginImport(sourceURL: url.absoluteString, title: url.host ?? "") { try await CoverImageLoader.load(url) }
    }

    func importPhoto(_ data: Data) { beginImport(sourceURL: "", title: "") { data } }

    func importPhoto(_ item: PhotosPickerItem) {
        beginImport(sourceURL: "", title: "") {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CoverImageError.notImage }
            return data
        }
    }

    private func beginImport(sourceURL: String, title: String, load: @escaping @MainActor () async throws -> Data) {
        importTask?.cancel()
        let token = UUID()
        importRequest = token
        isImporting = true
        importError = nil
        selectedData = nil
        selectedURL = ""
        selectedTitle = ""
        importTask = Task { [weak self] in
            do {
                let raw = try await load()
                try Task.checkCancellation()
                guard let data = compactPhoto(raw), let image = UIImage(data: data),
                      image.size.width >= 20, image.size.height >= 20 else { throw CoverImageError.notImage }
                guard let self, token == self.importRequest else { return }
                self.selectedData = data
                self.selectedURL = sourceURL
                self.selectedTitle = title
                self.isImporting = false
                self.importTask = nil
            } catch {
                guard let self, !Task.isCancelled, token == self.importRequest else { return }
                switch error as? CoverImageError {
                case .tooLarge: self.importError = "Изображение слишком большое. Выберите файл до 12 МБ."
                case .notImage: self.importError = "Не удалось прочитать изображение. Выберите другую обложку или фото."
                default: self.importError = "Не удалось загрузить обложку. Попробуйте снова или выберите другой источник."
                }
                self.isImporting = false
                self.importTask = nil
            }
        }
    }

    func cancel() {
        searchRequest = UUID()
        importRequest = UUID()
        searchTask?.cancel()
        importTask?.cancel()
        searchTask = nil
        importTask = nil
        isSearching = false
        isImporting = false
    }
}

private enum CoverImageLoader {
    static func load(_ url: URL) async throws -> Data {
        if await CoverTestFixture.enabled {
            guard let data = await CoverTestFixture.image(for: url.absoluteString) else { throw CoverImageError.unavailable }
            return data
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral, delegate: HTTPSCoverRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        try CoverSearch.validateImageResponse(response)
        var data = Data()
        data.reserveCapacity(min(Int(max(0, response.expectedContentLength)), CoverSearch.maximumImageBytes))
        for try await byte in bytes {
            guard data.count < CoverSearch.maximumImageBytes else { throw CoverImageError.tooLarge }
            data.append(byte)
            if data.count.isMultiple(of: 65_536) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        guard !data.isEmpty else { throw CoverImageError.notImage }
        return data
    }
}

private final class HTTPSCoverRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { CoverSearch.imageURL($0.absoluteString) } == nil ? nil : request)
    }
}

@MainActor
private enum CoverTestFixture {
    static var enabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--cover-test-fixture")
        #else
        return false
        #endif
    }

    static let books = [
        CatalogBook(id: "fixture-cover", title: "Альтернативная обложка", author: "Другой автор", language: "en", coverURL: "https://cover-fixture.invalid/cover.jpg", sourceName: "Open Library"),
        CatalogBook(id: "fixture-broken", title: "Недоступная обложка", coverURL: "https://cover-fixture.invalid/broken.jpg", sourceName: "Open Library")
    ]

    static func image(for url: String) -> Data? {
        guard enabled, url == "https://cover-fixture.invalid/cover.jpg" else { return nil }
        return imageData
    }

    private static let imageData: Data? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 360), format: format)
        return renderer.image { context in
            UIColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 360))
            ("BOOKREIGN" as NSString).draw(at: CGPoint(x: 24, y: 150), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
        }.jpegData(compressionQuality: 0.85)
    }()
}
