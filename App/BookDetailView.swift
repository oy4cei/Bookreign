import SwiftUI
import LibraryCore
import BookCatalog

struct BookDetailView: View {
    let editionID: UUID
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var addingCopy = false
    @State private var deleting = false
    @State private var findingMetadata = false
    @State private var choosingCover = false
    @State private var loanCopy: BookCopy?
    @State private var moveCopy: BookCopy?
    @State private var returnLoan: BookLoan?
    @State private var copyToDelete: BookCopy?
    private var edition: BookEdition? { store.snapshot.editions.first { $0.id == editionID } }
    var body: some View {
        Group {
            if let edition {
                List {
                    Section {
                        VStack(spacing: 16) {
                            BookCover(edition: edition, large: true).frame(width: 154, height: 226).shadow(color: .black.opacity(0.17), radius: 12, y: 7)
                                .accessibilityElement(children: .ignore)
                                .accessibilityHidden(false)
                                .accessibilityLabel(L("Обложка книги"))
                                .accessibilityValue(edition.coverData != nil ? L("Своя обложка") : (edition.coverURL.isEmpty ? L("Обложка не выбрана") : L("Из каталога")))
                                .accessibilityIdentifier("bookCover")
                            Button(edition.coverData == nil && edition.coverURL.isEmpty ? L("Добавить обложку") : L("Изменить обложку"), systemImage: "photo.badge.plus") { choosingCover = true }
                                .buttonStyle(ArchiveSecondaryButtonStyle())
                                .accessibilityIdentifier("coverEditorButton")
                            VStack(spacing: 7) {
                                Text(displayBookTitle(edition)).font(.system(.title2, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                                if !edition.author.isEmpty { Text(edition.author).foregroundStyle(Color.archiveSecondary).multilineTextAlignment(.center) }
                                Text(languageName(edition.language)).font(.caption).foregroundStyle(Color.forest).padding(.top, 3)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 16)
                    }.listRowBackground(Color.clear)
                    if ISBN.normalize(edition.isbn) != nil && (edition.hasPlaceholderTitle || edition.author.isEmpty) {
                        Section {
                            Button(L("Найти данные по ISBN"), systemImage: "sparkle.magnifyingglass") { findingMetadata = true }
                                .accessibilityIdentifier("findBookMetadata")
                        } footer: { Text(L("Можно заполнить название, автора и обложку, сохранив экземпляры, места и историю выдачи.")) }
                            .archiveRow()
                    }
                    Section(L("Где находится")) {
                        ForEach(store.copies(for: editionID)) { copy in
                            VStack(alignment: .leading, spacing: 10) {
                                if let loan = store.snapshot.activeLoan(for: copy.id) {
                                    Label(L("У \(loan.borrower)"), systemImage: "person.crop.circle").font(.system(.headline, design: .serif)).foregroundStyle(Color.forest)
                                    Text(L("Место хранения: \(store.locationName(copy.locationID))\(copy.shelf.isEmpty ? "" : " · " + copy.shelf)")).font(.caption).foregroundStyle(Color.archiveSecondary)
                                    if let due = loan.dueAt { Text(L("Вернуть до \(L10n.date(due))")).font(.caption).foregroundStyle(due < .now ? Color.red : Color.archiveSecondary) }
                                    Button(L("Книгу вернули"), systemImage: "arrow.uturn.backward") { returnLoan = loan }.buttonStyle(ArchiveSecondaryButtonStyle())
                                } else {
                                    Label(store.locationName(copy.locationID), systemImage: "mappin.and.ellipse").font(.system(.headline, design: .serif))
                                    if !copy.shelf.isEmpty { Text(copy.shelf).font(.subheadline).foregroundStyle(Color.archiveSecondary) }
                                    HStack {
                                        Button(L("Дать почитать"), systemImage: "person.badge.plus") { loanCopy = copy }
                                        Spacer()
                                        Button { moveCopy = copy } label: { Image(systemName: "tray.and.arrow.down") }.accessibilityLabel(L("Переместить экземпляр"))
                                    }.buttonStyle(ArchiveSecondaryButtonStyle())
                                }
                            }.padding(.vertical, 5)
                                .swipeActions(edge: .trailing) { Button(L("Удалить"), role: .destructive) { copyToDelete = copy } }
                        }
                        Button(L("Добавить ещё экземпляр"), systemImage: "plus") { addingCopy = true }
                    }.archiveRow()
                    if !edition.isbn.isEmpty || !edition.publisher.isEmpty || !edition.year.isEmpty {
                        Section(L("Об издании")) {
                            if !edition.isbn.isEmpty { LabeledContent("ISBN", value: edition.isbn).textSelection(.enabled) }
                            if !edition.publisher.isEmpty { LabeledContent(L("Издательство"), value: edition.publisher) }
                            if !edition.year.isEmpty { LabeledContent(L("Год"), value: edition.year) }
                        }.archiveRow()
                    }
                    if !edition.notes.isEmpty { Section(L("Заметки")) { Text(edition.hasPlaceholderTitle && edition.notes == "Данные издания нужно заполнить." ? L("Данные издания нужно заполнить.") : edition.notes).textSelection(.enabled) }.archiveRow() }
                    if !edition.genres.isEmpty {
                        Section(L("Жанры")) {
                            Text(edition.genres.joined(separator: "; ")).textSelection(.enabled)
                        }.archiveRow()
                    }
                    let copyIDs = Set(store.copies(for: editionID).map(\.id))
                    let history = store.snapshot.loans.filter { copyIDs.contains($0.copyID) && $0.returnedAt != nil }.sorted { $0.loanedAt > $1.loanedAt }
                    if !history.isEmpty {
                        Section(L("История выдачи")) {
                            ForEach(history) { loan in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(loan.borrower)
                                    Text("\(L10n.date(loan.loanedAt)) — \(L10n.date(loan.returnedAt!))").font(.caption).foregroundStyle(Color.archiveSecondary)
                                }
                            }
                        }.archiveRow()
                    }
                }.listStyle(.insetGrouped)
                    .archiveScreen()
                    .toolbar {
                        ArchiveToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button(L("Редактировать"), systemImage: "pencil") { editing = true }
                                if ISBN.normalize(edition.isbn) != nil {
                                    Button(L("Найти данные по ISBN"), systemImage: "magnifyingglass") { findingMetadata = true }
                                }
                                Button(L("Удалить из библиотеки"), systemImage: "trash", role: .destructive) { deleting = true }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                    .sheet(isPresented: $editing) { EditEditionView(edition: edition) }
                    .sheet(isPresented: $addingCopy) { AddCopyView(edition: edition) }
                    .sheet(isPresented: $findingMetadata) { BookMetadataView(editionID: editionID) }
                    .sheet(isPresented: $choosingCover) {
                        CoverPickerSheet(edition: edition) { data, sourceURL in
                            _ = store.update { state in
                                guard let index = state.editions.firstIndex(where: { $0.id == editionID }) else { return }
                                state.editions[index].coverData = data
                                state.editions[index].coverURL = sourceURL
                            }
                        }
                    }
            } else {
                ContentUnavailableView(L("Книга удалена"), systemImage: "book.closed")
            }
        }
        .archiveScreen()
        .navigationTitle(L("Книга")).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $loanCopy) { LoanEditorView(copy: $0) }
        .sheet(item: $moveCopy) { MoveCopiesView(copyIDs: [$0.id]) {} }
        .sheet(item: $returnLoan) { ReturnLoanView(loan: $0) }
        .confirmationDialog(L("Удалить книгу и все её экземпляры? История выдачи тоже будет удалена."), isPresented: $deleting, titleVisibility: .visible) {
            Button(L("Удалить книгу"), role: .destructive) { if store.removeEdition(editionID) { dismiss() } }
        }
        .confirmationDialog(L("Удалить этот экземпляр и его историю выдачи?"), isPresented: Binding(get: { copyToDelete != nil }, set: { if !$0 { copyToDelete = nil } }), titleVisibility: .visible) {
            Button(L("Удалить экземпляр"), role: .destructive) { if let copy = copyToDelete { _ = store.removeCopy(copy.id) }; copyToDelete = nil }
        }
    }
}

struct EditionFields: View {
    @Binding var edition: BookEdition
    var body: some View {
        Section(L("Книга")) {
            TextField(L("Название *"), text: $edition.title, axis: .vertical).accessibilityIdentifier("bookTitle")
            TextField(L("Автор"), text: $edition.author).accessibilityIdentifier("bookAuthor")
            Picker(L("Язык издания"), selection: $edition.language) { ForEach(bookLanguages, id: \.self) { Text(languageName($0)).tag($0) } }
        }.archiveRow()
        GenreFields(genres: $edition.genres)
        Section(L("Подробности — необязательно")) {
            ISBNInputField(text: $edition.isbn)
            TextField(L("Издательство"), text: $edition.publisher)
            TextField(L("Год издания"), text: $edition.year).keyboardType(.numberPad)
            TextField(L("Заметки"), text: $edition.notes, axis: .vertical).lineLimit(3...7)
        }.archiveRow()
    }
}

struct EditEditionView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var edition: BookEdition
    @State private var photoLoading = false
    var body: some View {
        NavigationStack {
            Form {
                EditionFields(edition: $edition)
                CoverEditor(edition: $edition, isLoading: $photoLoading)
            }.archiveScreen().navigationTitle(L("Редактировать"))
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ArchiveToolbarItem(placement: .confirmationAction) { Button(L("Сохранить")) {
                        if store.update({ state in if let i = state.editions.firstIndex(where: { $0.id == edition.id }) { state.editions[i] = edition } }) { dismiss() }
                    }.disabled(photoLoading || edition.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}

struct AddCopyView: View {
    let edition: BookEdition
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var location: UUID?
    @State private var shelf = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(displayBookTitle(edition)).font(.system(.headline, design: .serif)); Text(L("Это отдельный физический экземпляр того же издания.")).font(.subheadline).foregroundStyle(Color.archiveSecondary) }.archiveRow()
                LocationFields(location: $location, shelf: $shelf)
            }.archiveScreen().navigationTitle(L("Ещё экземпляр"))
                .onAppear { location = store.snapshot.locations.first?.id }
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ArchiveToolbarItem(placement: .confirmationAction) { Button(L("Добавить")) { if let location, store.add(edition, location: location, shelf: shelf, existingID: edition.id) { dismiss() } }.disabled(location == nil) }
                }
        }
    }
}

struct LocationFields: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var location: UUID?
    @Binding var shelf: String
    var body: some View {
        Section(L("Место хранения")) {
            Picker(L("Место"), selection: $location) {
                Text(L("Выберите место")).tag(nil as UUID?)
                ForEach(store.snapshot.locations) { Text(store.locationName($0.id)).tag(Optional($0.id)) }
            }
            TextField(L("Комната или полка — необязательно"), text: $shelf)
        }.archiveRow()
    }
}

struct MoveCopiesView: View {
    let copyIDs: Set<UUID>
    var onDone: () -> Void
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var location: UUID?
    @State private var shelf = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(L("Экземпляров: \(copyIDs.count)")); Text(L("Для выданных книг изменится место, куда они вернутся.")).font(.caption).foregroundStyle(Color.archiveSecondary) }.archiveRow()
                LocationFields(location: $location, shelf: $shelf)
            }.archiveScreen().navigationTitle(L("Переместить"))
                .onAppear { location = store.snapshot.locations.first?.id }
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ArchiveToolbarItem(placement: .confirmationAction) { Button(L("Готово")) {
                        guard let location else { return }
                        if store.update({ state in for i in state.copies.indices where copyIDs.contains(state.copies[i].id) { state.copies[i].locationID = location; state.copies[i].shelf = shelf } }) { onDone(); dismiss() }
                    }.disabled(location == nil) }
                }
        }
    }
}
