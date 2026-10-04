import SwiftUI
import LibraryCore
import BookCatalog

struct BookMetadataView: View {
    let editionID: UUID
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var candidates: [CatalogBook] = []
    @State private var selected: String?
    @State private var message: LocalizedMessage?
    @State private var attempt = UUID()

    private var current: BookEdition? { store.snapshot.editions.first { $0.id == editionID } }
    private var chosen: CatalogBook? { candidates.first { $0.id == selected } }
    private var preview: BookEdition? {
        guard let current, let chosen else { return nil }
        return current.fillingMissingMetadata(from: incoming(chosen))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("ISBN", value: current?.isbn ?? "")
                    if loading { ProgressView(L("Ищу данные издания…")) }
                    if let message { Text(L(message)).font(.subheadline).foregroundStyle(Color.archiveSecondary) }
                    if !loading && candidates.isEmpty {
                        Button(L("Повторить поиск"), systemImage: "arrow.clockwise") { attempt = UUID() }
                    }
                }.archiveRow()
                if candidates.count > 1 {
                    Section(L("Выберите сведения")) {
                        ForEach(candidates) { candidate in
                            Button { selected = candidate.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.title).font(.system(.body, design: .serif)).foregroundStyle(Color.archiveText)
                                        Text(candidate.author).font(.caption).foregroundStyle(Color.archiveSecondary)
                                    }
                                    Spacer()
                                    if selected == candidate.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }.archiveRow()
                }
                if let preview {
                    Section(L("Карточка после заполнения")) {
                        HStack(alignment: .top, spacing: 16) {
                            BookCover(edition: preview, large: true).frame(width: 82, height: 121)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(displayBookTitle(preview)).font(.system(.headline, design: .serif))
                                Text(preview.author).foregroundStyle(Color.archiveSecondary)
                                Text(languageName(preview.language)).font(.caption)
                            }
                        }.padding(.vertical, 8)
                        if !preview.publisher.isEmpty { LabeledContent(L("Издательство"), value: preview.publisher) }
                        if !preview.year.isEmpty { LabeledContent(L("Год"), value: preview.year) }
                        if !preview.genres.isEmpty { LabeledContent(L("Жанры"), value: preview.genres.joined(separator: "; ")) }
                        if let chosen, let sourceURL = URL(string: chosen.sourceURL), sourceURL.scheme == "https" {
                            Link(L("Источник: \(catalogSourceDisplayName(chosen.sourceName))"), destination: sourceURL).font(.subheadline)
                        }
                    }.archiveRow()
                    Section {
                        Button(L("Сохранить данные"), systemImage: "checkmark.circle") { apply() }
                            .buttonStyle(ArchivePrimaryButtonStyle())
                            .accessibilityIdentifier("applyBookMetadata")
                            .disabled(preview == current || loading)
                    } footer: {
                        Text(preview == current ? L("Все эти сведения уже заполнены. Изменить их можно через «Редактировать».") : L("Заполнятся только пустые поля и служебное название с ISBN. Ваши исправления, фото, места хранения и выдачи сохранятся."))
                    }.archiveRow()
                }
            }
            .archiveScreen()
            .navigationTitle(L("Данные издания")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Закрыть")) { dismiss() } } }
            .task(id: attempt) { await lookup() }
        }
    }

    private func incoming(_ result: CatalogBook) -> BookEdition {
        BookEdition(title: result.title, author: result.author, isbn: result.isbn, language: result.language, publisher: result.publisher, year: result.year, coverURL: result.coverURL, genres: result.genres)
    }

    @MainActor private func lookup() async {
        guard let isbn = current?.isbn, let canonical = ISBN.canonical(isbn) else {
            message = "Проверьте ISBN в редакторе книги."; loading = false; return
        }
        loading = true; message = nil; candidates = []; selected = nil
        do {
            let found = try await CatalogService.client().lookup(isbn: isbn)
            guard !Task.isCancelled else { return }
            candidates = found.filter { ISBN.canonical($0.isbn) == canonical }
            selected = candidates.first?.id
            if candidates.isEmpty { message = "В подключённых источниках пока нет точного совпадения по ISBN. Книгу можно заполнить вручную." }
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            message = "Поиск не завершён: \(L10n.error(error))"; loading = false
        }
    }

    private func apply() {
        guard let chosen, let current, let isbn = ISBN.canonical(current.isbn), ISBN.canonical(chosen.isbn) == isbn else { return }
        let metadata = incoming(chosen)
        if store.update({ state in
            guard let index = state.editions.firstIndex(where: { $0.id == editionID }), ISBN.canonical(state.editions[index].isbn) == isbn else { return }
            state.editions[index] = state.editions[index].fillingMissingMetadata(from: metadata)
        }) { dismiss() }
    }
}
