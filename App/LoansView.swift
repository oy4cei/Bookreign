import SwiftUI
import LibraryCore

struct LoansView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var returning: BookLoan?
    var body: some View {
        Group {
            if store.activeLoans.isEmpty {
                EmptyLibraryView(title: L("Все книги на месте"), message: L("Откройте книгу и нажмите «Дать почитать». Здесь появятся получатель и срок возврата."), symbol: "person.crop.circle.badge.checkmark")
            } else {
                List {
                    Section { Text(L("Помните, у кого ваши книги. Срок возврата можно не указывать.")).font(.subheadline).foregroundStyle(Color.archiveSecondary) }.archiveRow()
                    ForEach(store.activeLoans) { loan in
                        if let edition = store.edition(for: loan.copyID) {
                            Section {
                                NavigationLink { BookDetailView(editionID: edition.id) } label: {
                                    HStack(spacing: 14) {
                                        BookCover(edition: edition).frame(width: 49, height: 72)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(displayBookTitle(edition)).font(.system(.headline, design: .serif)).lineLimit(2)
                                            Label(loan.borrower, systemImage: "person").font(.subheadline).foregroundStyle(Color.forest)
                                            if let due = loan.dueAt {
                                                Text(due < .now ? L("Срок прошёл: \(L10n.date(due))") : L("До \(L10n.date(due))")).font(.caption).foregroundStyle(due < .now ? Color.red : Color.archiveSecondary)
                                            } else { Text(L("Без срока возврата")).font(.caption).foregroundStyle(Color.archiveSecondary) }
                                        }
                                    }
                                }
                                Button(L("Отметить возврат"), systemImage: "arrow.uturn.backward") { returning = loan }
                            }.archiveRow()
                        }
                    }
                }.archiveScreen()
            }
        }.archiveScreen().navigationTitle(L("Выдано")).background(Color.paper)
            .sheet(item: $returning) { ReturnLoanView(loan: $0) }
    }
}

struct LoanEditorView: View {
    let copy: BookCopy
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var borrower = ""
    @State private var hasDue = false
    @State private var loanedAt = Date()
    @State private var dueAt = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    private var names: [String] { Array(Set(store.snapshot.loans.map(\.borrower))).sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.edition(for: copy.id).map(displayBookTitle) ?? L("Книга")).font(.system(.headline, design: .serif))
                    Text(L("Место хранения: \(store.locationName(copy.locationID))")).font(.caption).foregroundStyle(Color.archiveSecondary)
                }.archiveRow()
                Section(L("Кому дали")) {
                    TextField(L("Имя получателя *"), text: $borrower).textContentType(.name).accessibilityIdentifier("borrowerName")
                    if !names.isEmpty { Menu(L("Выбрать из истории")) { ForEach(names, id: \.self) { name in Button(name) { borrower = name } } } }
                    DatePicker(L("Дата выдачи"), selection: $loanedAt, in: ...Date(), displayedComponents: .date)
                }.archiveRow()
                Section {
                    Toggle(L("Указать срок возврата"), isOn: $hasDue).tint(.archiveControlFill)
                    if hasDue { DatePicker(L("Вернуть до"), selection: $dueAt, in: Calendar.current.startOfDay(for: loanedAt)..., displayedComponents: .date) }
                } footer: { Text(L("Срок будет виден в разделе «Выдано». Уведомления в этой версии не отправляются.")) }
                    .archiveRow()
            }.archiveScreen().navigationTitle(L("Дать почитать"))
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ArchiveToolbarItem(placement: .confirmationAction) { Button(L("Сохранить")) {
                        let loan = BookLoan(copyID: copy.id, borrower: borrower.trimmingCharacters(in: .whitespacesAndNewlines), loanedAt: loanedAt, dueAt: hasDue ? Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: dueAt) : nil)
                        if store.update({ $0.loans.append(loan) }) { dismiss() }
                    }.disabled(borrower.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}

struct ReturnLoanView: View {
    let loan: BookLoan
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var location: UUID?
    @State private var shelf = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(store.edition(for: loan.copyID).map(displayBookTitle) ?? L("Книга")).font(.system(.headline, design: .serif)); Text(L("Возвращает: \(loan.borrower)")).foregroundStyle(Color.archiveSecondary) }.archiveRow()
                LocationFields(location: $location, shelf: $shelf)
            }.archiveScreen().navigationTitle(L("Книга вернулась"))
                .onAppear { if let copy = store.snapshot.copies.first(where: { $0.id == loan.copyID }) { location = copy.locationID; shelf = copy.shelf } }
                .toolbar {
                    ArchiveToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ArchiveToolbarItem(placement: .confirmationAction) { Button(L("Вернуть")) {
                        guard let location else { return }
                        if store.update({ state in
                            if let i = state.loans.firstIndex(where: { $0.id == loan.id }) { state.loans[i].returnedAt = .now }
                            if let i = state.copies.firstIndex(where: { $0.id == loan.copyID }) { state.copies[i].locationID = location; state.copies[i].shelf = shelf }
                        }) { dismiss() }
                    }.disabled(location == nil) }
                }
        }
    }
}
