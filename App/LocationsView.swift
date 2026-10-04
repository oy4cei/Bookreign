import SwiftUI
import LibraryCore

struct LocationsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var adding = false
    @State private var editing: StorageLocation?
    @State private var deleting: StorageLocation?
    var body: some View {
        NavigationStack {
            List {
                Section { Text(L("У каждой книги есть своё место. Комнату или полку можно указать в карточке экземпляра.")).foregroundStyle(Color.archiveSecondary).font(.subheadline) }.archiveRow()
                Section {
                    NavigationLink { LoansView() } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.badge.clock")
                                .font(.title2).foregroundStyle(Color.forest)
                                .frame(width: 46, height: 50)
                                .background(Color.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L("Выдано")).font(.system(.headline, design: .serif))
                                Text(L("Экземпляров: \(store.activeLoans.count)"))
                                    .font(.subheadline).foregroundStyle(Color.archiveSecondary)
                            }
                        }.padding(.vertical, 5)
                    }.accessibilityIdentifier("loansLocation")
                }.archiveRow()
                ForEach(store.snapshot.locations) { location in
                    NavigationLink { LocationDetailView(locationID: location.id) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: location.symbol).font(.title2).foregroundStyle(Color.forest).frame(width: 46, height: 50).background(Color.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.locationName(location.id)).font(.system(.headline, design: .serif))
                                Text(L("Экземпляров: \(store.snapshot.copies.filter { $0.locationID == location.id }.count)")).font(.subheadline).foregroundStyle(Color.archiveSecondary)
                            }
                        }.padding(.vertical, 5)
                    }.archiveRow().swipeActions {
                        Button(L("Удалить"), role: .destructive) { deleting = location }
                        Button(L("Изменить")) { editing = location }.tint(.archiveControlFill)
                    }.contextMenu {
                        Button(L("Изменить"), systemImage: "pencil") { editing = location }
                        Button(L("Удалить"), systemImage: "trash", role: .destructive) { deleting = location }
                    }
                }
                Section { Button(L("Добавить место"), systemImage: "plus") { adding = true } }.archiveRow()
            }
                .safeAreaInset(edge: .top, spacing: 0) {
                    ArchivePageHeader(title: L("Места хранения"))
                }
                .archiveScreen().navigationTitle(L("Места хранения"))
                .toolbar { ArchiveToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(L("Добавить место")) } }
                .sheet(isPresented: $adding) { LocationEditorView() }
                .sheet(item: $editing) { LocationEditorView(existing: $0) }
                .alert(L("Удалить место?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    if let location = deleting, !store.snapshot.copies.contains(where: { $0.locationID == location.id }), store.snapshot.locations.count > 1 {
                        Button(L("Удалить"), role: .destructive) { _ = store.update { $0.locations.removeAll { $0.id == location.id } }; deleting = nil }
                    }
                    Button(L("Отмена"), role: .cancel) { deleting = nil }
                } message: {
                    if let location = deleting, store.snapshot.copies.contains(where: { $0.locationID == location.id }) { Text(L("Сначала переместите книги из этого места в другое. Книги, которые дали почитать, тоже учитываются.")) }
                    else if store.snapshot.locations.count <= 1 { Text(L("В библиотеке должно остаться хотя бы одно место.")) }
                    else { Text(L("Пустое место будет удалено.")) }
                }
        }
    }
}

struct LocationDetailView: View {
    let locationID: UUID
    @EnvironmentObject private var store: LibraryStore
    @State private var add = false
    var body: some View {
        List {
            let copies = store.snapshot.copies.filter { $0.locationID == locationID }
            if copies.isEmpty { Text(L("Здесь пока нет книг")).foregroundStyle(Color.archiveSecondary).archiveRow() }
            ForEach(copies) { copy in
                if let edition = store.snapshot.editions.first(where: { $0.id == copy.editionID }) {
                    NavigationLink { BookDetailView(editionID: edition.id) } label: {
                        HStack(spacing: 13) {
                            BookCover(edition: edition).frame(width: 42, height: 62)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(displayBookTitle(edition)).font(.system(.headline, design: .serif))
                                if let loan = store.snapshot.activeLoan(for: copy.id) { Text(L("У \(loan.borrower)")).font(.caption).foregroundStyle(Color.forest) }
                                else { Text(copy.shelf.isEmpty ? L("Полка не указана") : copy.shelf).font(.caption).foregroundStyle(Color.archiveSecondary) }
                            }
                        }
                    }.archiveRow()
                }
            }
        }.archiveScreen().navigationTitle(store.locationName(locationID))
            .toolbar { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel(L("Добавить книгу сюда")) }
            .sheet(isPresented: $add) { AddBookView(initialLocation: locationID) }
    }
}

struct LocationEditorView: View {
    var existing: StorageLocation? = nil
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "house"
    private let symbols = ["house", "tree", "building.2", "books.vertical", "archivebox", "briefcase", "heart"]
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Название места")) { TextField(L("Например, у родителей"), text: $name).accessibilityIdentifier("locationName") }.archiveRow()
                Section(L("Значок")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                        ForEach(symbols, id: \.self) { icon in
                            Button { symbol = icon } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(symbol == icon ? Color.archiveActionText : Color.forest)
                                    .background(symbol == icon ? Color.forestFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.archiveRule, lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(locationIconName(icon))
                            .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                        }
                    }
                }.archiveRow()
            }.archiveScreen().navigationTitle(existing == nil ? L("Новое место") : L("Изменить место"))
                .onAppear { if let existing { name = store.locationName(existing.id); symbol = existing.symbol } }
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ArchiveToolbarItem(placement: .confirmationAction) { Button(L("Сохранить")) {
                        let item = StorageLocation(id: existing?.id ?? UUID(), name: existing.map { name == store.locationName($0.id) ? $0.name : name.trimmingCharacters(in: .whitespacesAndNewlines) } ?? name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol)
                        if store.update({ state in if let i = state.locations.firstIndex(where: { $0.id == item.id }) { state.locations[i] = item } else { state.locations.append(item) } }) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}
