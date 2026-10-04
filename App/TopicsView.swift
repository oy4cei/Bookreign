import SwiftUI
import LibraryCore

struct TopicsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var query = ""
    @State private var author: LibraryBrowse.Filter = .all
    @State private var genre: LibraryBrowse.Filter = .all
    @State private var ascending = true
    @FocusState private var searchFocused: Bool

    private var books: [BookEdition] {
        LibraryBrowse.editions(in: store.snapshot, query: query, author: author, genre: genre,
                               ascending: ascending, locale: AppPreferences.shared.locale)
    }
    private var hasFilters: Bool { !query.isEmpty || author != .all || genre != .all || !ascending }

    var body: some View {
        NavigationStack {
            List {
                if !store.isReady {
                    EmptyLibraryView(title: L("Библиотека недоступна"), message: L("Не удалось открыть файл данных. Закройте и откройте приложение. Существующая база не перезаписывается."), symbol: "externaldrive.badge.exclamationmark")
                        .listRowBackground(Color.clear)
                } else if store.snapshot.editions.isEmpty {
                    EmptyLibraryView(title: L("Темы вашей библиотеки"), message: L("Добавьте книги на вкладке «Книги». Здесь можно будет выбрать автора, жанр и порядок по названию."), symbol: "line.3.horizontal.decrease.circle")
                        .listRowBackground(Color.clear)
                } else {
                    search
                    filters
                    Section {
                        if books.isEmpty {
                            EmptyLibraryView(title: L("Книг не найдено"), message: L("Попробуйте другое название, автора или измените фильтры."), symbol: "magnifyingglass")
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(books) { edition in
                                NavigationLink { BookDetailView(editionID: edition.id) } label: {
                                    bookRow(edition)
                                }
                                .archiveRow()
                                .accessibilityIdentifier("topicsBook-\(edition.title)")
                            }
                        }
                    } header: {
                        Text(L("Найдено изданий: \(books.count)"))
                            .accessibilityIdentifier("topicsResultCount")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                ArchivePageHeader(title: L("Темы"))
            }
            .archiveScreen()
            .navigationTitle(L("Темы"))
        }
    }

    private var search: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.archiveSecondary).accessibilityHidden(true)
                TextField(L("Название, автор или ISBN"), text: $query,
                          prompt: Text(L("Название, автор или ISBN")).foregroundStyle(Color.archiveSecondary))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("topicsSearch")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.archiveSecondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Очистить поиск"))
                }
            }
        }.archiveRow()
    }

    private var filters: some View {
        Section {
            Picker(L("Автор"), selection: $author) {
                Text(L("Все авторы")).tag(LibraryBrowse.Filter.all)
                Text(L("Автор не указан")).tag(LibraryBrowse.Filter.missing)
                ForEach(availableValues(LibraryBrowse.authors(in: store.snapshot, locale: AppPreferences.shared.locale), including: author), id: \.self) { value in
                    Text(value).tag(LibraryBrowse.Filter.value(value))
                }
            }
            .accessibilityIdentifier("topicsAuthorPicker")
            Picker(L("Жанр"), selection: $genre) {
                Text(L("Все жанры")).tag(LibraryBrowse.Filter.all)
                Text(L("Без жанра")).tag(LibraryBrowse.Filter.missing)
                ForEach(availableValues(LibraryBrowse.genres(in: store.snapshot, locale: AppPreferences.shared.locale), including: genre), id: \.self) { value in
                    Text(value).tag(LibraryBrowse.Filter.value(value))
                }
            }
            .accessibilityIdentifier("topicsGenrePicker")
            Picker(L("Сортировка"), selection: $ascending) {
                Text(L("Название: А–Я")).tag(true)
                Text(L("Название: Я–А")).tag(false)
            }
            .accessibilityIdentifier("topicsSortPicker")
            if hasFilters {
                Button(L("Сбросить фильтры"), systemImage: "arrow.counterclockwise", action: resetFilters)
                    .accessibilityIdentifier("topicsResetFilters")
            }
        } header: {
            Text(L("Фильтры"))
        } footer: {
            Text(L("Жанры можно добавить или изменить в карточке книги."))
        }
        .archiveRow()
        .pickerStyle(.menu)
    }

    private func bookRow(_ edition: BookEdition) -> some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(edition: edition).frame(width: 44, height: 65)
            VStack(alignment: .leading, spacing: 5) {
                Text(displayBookTitle(edition)).font(.system(.headline, design: .serif))
                Text(edition.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Автор не указан") : edition.author)
                    .font(.subheadline).foregroundStyle(Color.archiveSecondary)
                if !edition.genres.isEmpty {
                    Text(edition.genres.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color.forest)
                }
            }
        }
        .padding(.vertical, 5)
    }

    // Keep a selected value available if the last matching book is edited or removed.
    // The empty result then remains understandable, and Reset is still available.
    private func availableValues(_ values: [String], including selection: LibraryBrowse.Filter) -> [String] {
        guard case let .value(selected) = selection, !values.contains(selected) else { return values }
        return values + [selected]
    }

    private func resetFilters() {
        query = ""
        author = .all
        genre = .all
        ascending = true
    }
}
