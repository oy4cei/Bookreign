import Foundation
import SwiftUI
import Combine
import LibraryCore

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot.empty
    @Published var errorMessage: LocalizedMessage?
    @Published private(set) var isReady = false
    @Published private(set) var canUndo = false
    private var database: LibraryDatabase?
    private var previous: LibrarySnapshot?

    init() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Polka", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
            var databaseName = isDemo ? "demo.sqlite" : "library.sqlite"
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                databaseName = "ui-testing.sqlite"
                if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                    let testURL = folder.appendingPathComponent(databaseName)
                    if FileManager.default.fileExists(atPath: testURL.path) { try FileManager.default.removeItem(at: testURL) }
                    UserDefaults.standard.removeObject(forKey: "pendingISBNs")
                }
            }
            #endif
            database = try LibraryDatabase(url: folder.appendingPathComponent(databaseName))
            snapshot = try database!.load()
            isReady = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--seed-missing-isbn"), snapshot.editions.isEmpty,
               let location = snapshot.locations.first?.id {
                _ = add(BookEdition(title: "Книга · 9789664481974", isbn: "9789664481974", notes: "Данные издания нужно заполнить."), location: location, shelf: "Детская")
            }
            #endif
            if isDemo && snapshot.editions.isEmpty { loadDemo() }
        } catch {
            errorMessage = "Не удалось открыть библиотеку. Данные сохранены на устройстве и не будут перезаписаны. \(L10n.error(error))"
        }
    }

    @discardableResult
    func update(_ change: (inout LibrarySnapshot) -> Void) -> Bool {
        guard isReady, let database else { errorMessage = "Библиотека недоступна для записи. Перезапустите приложение."; return false }
        var next = snapshot
        change(&next)
        do {
            try next.validate()
            try database.save(next)
            previous = snapshot
            snapshot = next
            canUndo = true
            return true
        } catch { errorMessage = "Изменение не сохранено. \(L10n.error(error))"; return false }
    }

    func undo() {
        guard let previous, let database else { return }
        do {
            try database.save(previous)
            snapshot = previous
            self.previous = nil
            canUndo = false
        } catch { errorMessage = .verbatim(L10n.error(error)) }
    }

    func add(_ edition: BookEdition, location: UUID, shelf: String, existingID: UUID? = nil) -> Bool {
        update { state in
            let id = existingID ?? edition.id
            if existingID == nil { state.editions.append(edition) }
            state.copies.append(BookCopy(editionID: id, locationID: location, shelf: shelf.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    func removeEdition(_ id: UUID) -> Bool {
        update { state in
            let copies = Set(state.copies.filter { $0.editionID == id }.map(\.id))
            state.loans.removeAll { copies.contains($0.copyID) }
            state.copies.removeAll { $0.editionID == id }
            state.editions.removeAll { $0.id == id }
        }
    }

    func removeCopy(_ id: UUID) -> Bool {
        update { state in
            guard let copy = state.copies.first(where: { $0.id == id }) else { return }
            state.loans.removeAll { $0.copyID == id }
            state.copies.removeAll { $0.id == id }
            if !state.copies.contains(where: { $0.editionID == copy.editionID }) { state.editions.removeAll { $0.id == copy.editionID } }
        }
    }

    func locationName(_ id: UUID) -> String {
        guard let location = snapshot.locations.first(where: { $0.id == id }) else { return L("Без места") }
        // Translate only built-in defaults, leaving custom location data untouched.
        switch (location.name, location.symbol) {
        case ("Дом", "house"): return L("Дом")
        case ("Дача", "tree"): return L("Дача")
        default: return location.name
        }
    }
    func copies(for edition: UUID) -> [BookCopy] { snapshot.copies.filter { $0.editionID == edition }.sorted { $0.addedAt < $1.addedAt } }
    func edition(for copy: UUID) -> BookEdition? {
        guard let item = snapshot.copies.first(where: { $0.id == copy }) else { return nil }
        return snapshot.editions.first { $0.id == item.editionID }
    }
    func restore(_ data: Data) throws -> Bool {
        let imported = try LibraryBackup.decode(data)
        return update { $0 = imported }
    }
    var activeLoans: [BookLoan] { snapshot.loans.filter { $0.returnedAt == nil }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) } }

    private func loadDemo() {
        var demo = LibrarySnapshot.empty
        let home = demo.locations[0].id, dacha = demo.locations[1].id
        let books = [
            BookEdition(title: "Тіні забутих предків", author: "Михайло Коцюбинський", language: "uk", year: "1911"),
            BookEdition(title: "The Little Prince", author: "Antoine de Saint-Exupéry", language: "en", year: "1943"),
            BookEdition(title: "Лісова пісня", author: "Леся Українка", language: "uk", year: "1911"),
            BookEdition(title: "Мастер и Маргарита", author: "Михаил Булгаков", language: "ru"),
            BookEdition(title: "The Art of Simple Living", author: "Shunmyo Masuno", language: "en"),
            BookEdition(title: "Місто", author: "Валер’ян Підмогильний", language: "uk", year: "1928")
        ]
        demo.editions = books
        demo.copies = books.enumerated().map { i, book in BookCopy(editionID: book.id, locationID: i == 3 ? dacha : home, shelf: i == 3 ? "Гостиная" : "Книжный шкаф") }
        demo.loans = [BookLoan(copyID: demo.copies[1].id, borrower: "Анна", loanedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!, dueAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()))]
        _ = update { $0 = demo }
        previous = nil; canUndo = false
    }
}

@MainActor
func languageName(_ code: String) -> String {
    switch code {
    case "uk": L("Украинский")
    case "ru": L("Русский")
    case "en": L("Английский")
    default: L("Другой / не указан")
    }
}
let bookLanguages = ["uk", "ru", "en", "other"]
