import SwiftUI
import LibraryCore

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var location: UUID?
    @State private var language = "all"
    @State private var loanedOnly = false
    @State private var preferences = AppPreferences.shared
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var showMove = false
    private var selectedCopyIDs: Set<UUID> {
        let visibleEditions = Set(books.map(\.id))
        return Set(store.snapshot.copies.filter { copy in
            selection.contains(copy.editionID) && visibleEditions.contains(copy.editionID)
            && (location == nil || copy.locationID == location)
            && (!loanedOnly || store.snapshot.activeLoan(for: copy.id) != nil)
        }.map(\.id))
    }
    private var books: [BookEdition] {
        store.snapshot.editions.filter { edition in
            let copies = store.copies(for: edition.id)
            return store.snapshot.matches(edition, query: query)
            && (language == "all" || edition.language == language)
            && copies.contains { copy in (location == nil || copy.locationID == location) && (!loanedOnly || store.snapshot.activeLoan(for: copy.id) != nil) }
        }.sorted { a, b in
            let da = store.copies(for: a.id).map(\.addedAt).max() ?? .distantPast
            let db = store.copies(for: b.id).map(\.addedAt).max() ?? .distantPast
            return da > db
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 18) {
                    searchControls
                    filterBar
                    if !store.isReady {
                        EmptyLibraryView(title: L("Библиотека недоступна"), message: L("Не удалось открыть файл данных. Закройте и откройте приложение. Существующая база не перезаписывается."), symbol: "externaldrive.badge.exclamationmark")
                    } else if store.snapshot.editions.isEmpty {
                        EmptyLibraryView(title: L("Каждой книге — своё место"), message: L("Отсканируйте ISBN или обложку. Сохраните любимые книги и всегда знайте, где они находятся."), actionTitle: L("Добавить первую книгу"), action: { showAdd = true }).padding(.top, 36)
                    } else if books.isEmpty {
                        EmptyLibraryView(title: L("Книг не найдено"), message: L("Попробуйте другое название, автора или измените фильтры."), symbol: "magnifyingglass", actionTitle: L("Сбросить фильтры")) { query = ""; location = nil; language = "all"; loanedOnly = false }
                    } else if preferences.libraryGrid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 230), spacing: 22)], alignment: .leading, spacing: 22) {
                            ForEach(books) { edition in bookLink(edition, compact: false) }
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(books) { edition in bookLink(edition, compact: true) }
                        }
                    }
                    }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .archiveScreen()
            .navigationTitle(L("Bookreign")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ArchiveToolbarItem(placement: .topBarLeading) { Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel(L("Настройки и резервная копия")).accessibilityIdentifier("settingsButton") }
                ArchiveToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { selecting.toggle(); selection.removeAll() } label: { Label(selecting ? L("Отменить выбор") : L("Выбрать книги"), systemImage: "checkmark.circle") }
                        if store.canUndo { Button(L("Отменить последнее изменение"), systemImage: "arrow.uturn.backward") { store.undo() } }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel(L("Действия с книгами"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if selecting {
                        Button(L("Отмена")) { selecting = false; selection.removeAll() }
                        Spacer()
                        Button(L("Переместить (\(selectedCopyIDs.count))"), systemImage: "tray.and.arrow.down") { showMove = true }
                            .buttonStyle(ArchivePrimaryButtonStyle()).disabled(selectedCopyIDs.isEmpty)
                    } else {
                        Button { showAdd = true } label: {
                            Label(L("Сканировать ISBN"), systemImage: "barcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ArchivePrimaryButtonStyle())
                        .accessibilityIdentifier("addBookButton")
                        .disabled(!store.isReady)
                    }
                }.padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Color.paper)
                    .overlay(alignment: .top) { Rectangle().fill(Color.archiveRule).frame(height: 0.5) }
            }
            .sheet(isPresented: $showAdd) { AddBookView(initialLocation: location) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showMove) {
                MoveCopiesView(copyIDs: selectedCopyIDs) { selecting = false; selection.removeAll() }
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Моя библиотека"))
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            librarySummary
        }
        .foregroundStyle(Color.archiveOnHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 22)
        .background(Color.archiveHeader)
    }
    private var searchControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    searchField
                    layoutControl
                }
            } else {
                HStack(spacing: 10) {
                    searchField
                    layoutControl
                }
            }
        }
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.archiveSecondary)
            TextField(L("Название, автор или ISBN"), text: $query,
                      prompt: Text(L("Название, автор или ISBN")).foregroundStyle(Color.archiveSecondary))
                .font(.subheadline)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("librarySearch")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.archiveSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel(L("Очистить поиск"))
            }
        }
        .padding(.leading, 12).padding(.trailing, query.isEmpty ? 12 : 0)
        .frame(minHeight: 48)
        .background(Color.archiveSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.archiveRule, lineWidth: 1) }
    }
    private var librarySummary: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    summaryEditions
                    Text("·")
                    summaryCopies
                    if !store.activeLoans.isEmpty { Text("·"); summaryLoans }
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    summaryEditions
                    summaryCopies
                    if !store.activeLoans.isEmpty { summaryLoans }
                }
            }.font(.caption).foregroundStyle(Color.archiveOnHeader.opacity(0.85))
    }
    private var summaryEditions: some View { Text(L("Изданий: \(store.snapshot.editions.count)")) }
    private var summaryCopies: some View { Text(L("Экземпляров: \(store.snapshot.copies.count)")) }
    private var summaryLoans: some View { Text(L("Выдано: \(store.activeLoans.count)")) }
    private var layoutControl: some View {
        HStack(spacing: 2) {
            layoutButton(grid: true, title: L("Показать обложками"), symbol: "square.grid.2x2", identifier: "libraryLayoutGrid")
            layoutButton(grid: false, title: L("Показать списком"), symbol: "list.bullet", identifier: "libraryLayoutList")
        }
        .padding(2)
        .background(Color.archiveSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.archiveRule, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Вид библиотеки"))
    }
    private func layoutButton(grid: Bool, title: String, symbol: String, identifier: String) -> some View {
        let selected = preferences.libraryGrid == grid
        return Button { preferences.libraryGrid = grid } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? Color.archiveActionText : Color.archiveSecondary)
                .background(selected ? Color.forestFill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(L("Все книги"), selected: location == nil && !loanedOnly) { location = nil; loanedOnly = false }
                ForEach(store.snapshot.locations) { item in
                    filterPill(store.locationName(item.id), selected: location == item.id && !loanedOnly) { location = item.id; loanedOnly = false }
                }
                filterPill(L("Выдано"), selected: loanedOnly) { loanedOnly.toggle(); location = nil }
                Menu {
                    Button(L("Все языки")) { language = "all" }
                    ForEach(bookLanguages, id: \.self) { code in Button(languageName(code)) { language = code } }
                } label: {
                    Label(language == "all" ? L("Язык") : languageName(language), systemImage: "globe")
                        .font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(Color.forest)
                        .background(Color.archiveSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.archiveRule, lineWidth: 1) }
                }
            }
        }.contentMargins(.trailing, 2)
    }
    private func filterPill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular)).padding(.horizontal, 15).frame(minHeight: 44)
                .foregroundStyle(selected ? Color.archiveActionText : Color.archiveText)
                .background(selected ? Color.forestFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.clear : Color.archiveRule, lineWidth: 1) }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    @ViewBuilder private func bookLink(_ edition: BookEdition, compact: Bool) -> some View {
        if selecting {
            Button { if selection.contains(edition.id) { selection.remove(edition.id) } else { selection.insert(edition.id) } } label: {
                bookCard(edition, compact: compact).overlay(alignment: .topTrailing) {
                    Image(systemName: selection.contains(edition.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).symbolRenderingMode(.palette)
                        .foregroundStyle(selection.contains(edition.id) ? Color.archiveActionText : Color.forest, Color.forestFill)
                        .background(Color.archiveSurface, in: Circle())
                        .padding(7)
                }
            }.buttonStyle(.plain)
        } else {
            NavigationLink { BookDetailView(editionID: edition.id) } label: { bookCard(edition, compact: compact) }.buttonStyle(.plain).accessibilityIdentifier("bookCard-\(edition.title)")
        }
    }
    private func bookCard(_ edition: BookEdition, compact: Bool) -> some View {
        let copies = store.copies(for: edition.id)
        let loaned = copies.filter { store.snapshot.activeLoan(for: $0.id) != nil }.count
        let place = Set(copies.map { store.locationName($0.locationID) }).sorted().joined(separator: ", ")
        return Group {
            if compact {
                HStack(spacing: 16) {
                    BookCover(edition: edition).frame(width: 60, height: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayBookTitle(edition)).font(.system(.headline, design: .serif)).lineLimit(2)
                        Text(edition.author.isEmpty ? L("Автор не указан") : edition.author).font(.subheadline).foregroundStyle(Color.archiveSecondary).lineLimit(1)
                        LocationChip(text: loaned > 0 ? L("Выдано: \(loaned) · \(place)") : place, symbol: loaned > 0 ? "person" : "mappin.and.ellipse")
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.archiveSecondary)
                }.padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.archiveRule).frame(height: 0.5) }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    BookCover(edition: edition, large: true).shadow(color: .black.opacity(0.12), radius: 7, x: 2, y: 6).padding(.bottom, 5)
                    Text(displayBookTitle(edition)).font(.system(.headline, design: .serif)).lineLimit(2, reservesSpace: true)
                    Text(edition.author.isEmpty ? L("Автор не указан") : edition.author).font(.caption).foregroundStyle(Color.archiveSecondary).lineLimit(1)
                    Label(loaned > 0 ? L("Выдано: \(loaned)") : place, systemImage: loaned > 0 ? "person" : "mappin.and.ellipse").font(.caption2.weight(.medium)).foregroundStyle(Color.forest).lineLimit(1)
                }.padding(.bottom, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.archiveRule).frame(height: 0.5) }
            }
        }.accessibilityElement(children: .combine)
    }
}
