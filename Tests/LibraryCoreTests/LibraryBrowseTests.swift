import Foundation
import SQLite3
import XCTest
@testable import LibraryCore

final class BookGenresTests: XCTestCase {
    func testGenresTrimEmptyValuesAndDeduplicateWithoutChangingFirstSpelling() {
        var edition = BookEdition(title: "Книга", genres: ["  П’ять історій ", "п'ять історій", "", "  ", "Фантастика", "фантастика", "Їжа", "Іжа"])
        XCTAssertEqual(edition.genres, ["П’ять історій", "Фантастика", "Їжа", "Іжа"])
        edition.genres = [" Детектив ", "ДЕТЕКТИВ", " "]
        XCTAssertEqual(edition.genres, ["Детектив"])
        edition.genres.append("детектив")
        XCTAssertEqual(edition.genres, ["Детектив"])
    }

    func testPreviousVersionBackupWithoutGenresStillRestoresEveryField() throws {
        let snapshot = try LibraryBackup.decode(Data("{\"version\":1,\"snapshot\":\(legacySnapshotJSON)}".utf8))
        XCTAssertEqual(snapshot.editions, [legacyEdition])
        XCTAssertEqual(snapshot.editions[0].genres, [])
        XCTAssertEqual(snapshot.copies.count, 1)
        XCTAssertEqual(snapshot.copies[0].shelf, "A-2")
        XCTAssertEqual(snapshot.locations[0].name, "Дача")
        XCTAssertEqual(snapshot.loans[0].borrower, "Олена")
    }

    func testPreviousVersionDatabaseWithoutGenresLoadsWithoutResettingRecords() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        let sql = "CREATE TABLE library_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL); PRAGMA user_version = 1; INSERT INTO library_snapshot VALUES(1, '\(legacySnapshotJSON)');"
        XCTAssertEqual(sqlite3_exec(connection, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)
        let database = try LibraryDatabase(url: url)
        let snapshot = try database.load()
        XCTAssertEqual(snapshot.editions, [legacyEdition])
        XCTAssertEqual(snapshot.copies.count, 1)
        XCTAssertEqual(snapshot.loans.count, 1)
        try database.save(snapshot)
        XCTAssertEqual(try LibraryDatabase(url: url).load(), snapshot)
    }

    func testGenresRoundTripThroughDatabaseAndBackup() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        var snapshot = try database.load()
        snapshot.editions = [BookEdition(title: "Місто", author: "Валер’ян Підмогильний", language: "uk", genres: ["Роман", "Класика"])]
        try database.save(snapshot)
        XCTAssertEqual(try LibraryDatabase(url: url).load(), snapshot)
        XCTAssertEqual(try LibraryBackup.decode(LibraryBackup.encode(snapshot)), snapshot)
        let encoded = String(decoding: try LibraryBackup.encode(snapshot), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"genres\""))
    }

    func testNewDecoderStillRejectsMissingRequiredFieldsAndInvalidGenres() throws {
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyEdition)) as? [String: Any])
        record.removeValue(forKey: "genres")
        for field in ["id", "title", "author", "isbn", "language", "publisher", "year", "coverURL", "notes"] {
            var incomplete = record
            incomplete.removeValue(forKey: field)
            XCTAssertThrowsError(try JSONDecoder().decode(BookEdition.self, from: JSONSerialization.data(withJSONObject: incomplete)), field)
        }
        record["genres"] = "Роман"
        XCTAssertThrowsError(try JSONDecoder().decode(BookEdition.self, from: JSONSerialization.data(withJSONObject: record)))
    }

    func testDecodedGenresAreNormalized() throws {
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyEdition)) as? [String: Any])
        record["genres"] = [" Роман ", "РОМАН", "", "Історія"]
        let decoded = try JSONDecoder().decode(BookEdition.self, from: JSONSerialization.data(withJSONObject: record))
        XCTAssertEqual(decoded.genres, ["Роман", "Історія"])
    }

    func testMetadataFillsEmptyGenresAndPreservesUserGenres() {
        let incoming = BookEdition(title: "Title", isbn: "9789664481974", genres: ["Fiction"])
        let empty = BookEdition(title: "Title", isbn: "9789664481974")
        XCTAssertEqual(empty.fillingMissingMetadata(from: incoming).genres, ["Fiction"])
        let edited = BookEdition(title: "Title", isbn: "9789664481974", genres: ["Мої книги"])
        XCTAssertEqual(edited.fillingMissingMetadata(from: incoming), edited)
        let differentISBN = BookEdition(title: "Other", isbn: "9789664481975", genres: ["Poetry"])
        XCTAssertEqual(empty.fillingMissingMetadata(from: differentISBN).genres, [])
    }

    func testCSVAppendsGenresAndEscapesTheirContents() {
        let edition = BookEdition(title: "Title", genres: ["=SUM(1,2)", "A \"quote\""])
        let csv = LibraryBackup.csv(LibrarySnapshot(editions: [edition]))
        XCTAssertTrue(csv.components(separatedBy: "\r\n")[0].hasSuffix(",notes,genres"))
        XCTAssertTrue(csv.contains("\"'=SUM(1,2); A \"\"quote\"\"\""))
    }

    private var legacyEdition: BookEdition {
        BookEdition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Місто", author: "Валер’ян Підмогильний", isbn: "9781234567890", language: "uk", publisher: "Видавництво", year: "2020", coverURL: "https://example.test/cover.jpg", coverData: Data([1, 2, 3]), notes: "Моя примітка")
    }

    private var legacySnapshotJSON: String {
        """
        {"editions":[{"id":"00000000-0000-0000-0000-000000000001","title":"Місто","author":"Валер’ян Підмогильний","isbn":"9781234567890","language":"uk","publisher":"Видавництво","year":"2020","coverURL":"https://example.test/cover.jpg","coverData":"AQID","notes":"Моя примітка"}],"copies":[{"id":"00000000-0000-0000-0000-000000000002","editionID":"00000000-0000-0000-0000-000000000001","locationID":"00000000-0000-0000-0000-000000000003","shelf":"A-2","addedAt":0}],"locations":[{"id":"00000000-0000-0000-0000-000000000003","name":"Дача","symbol":"tree"}],"loans":[{"id":"00000000-0000-0000-0000-000000000004","copyID":"00000000-0000-0000-0000-000000000002","borrower":"Олена","loanedAt":1}]}
        """
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("polka-genres-\(UUID().uuidString).sqlite")
    }
}

final class LibraryBrowseTests: XCTestCase {
    private let uk = Locale(identifier: "uk_UA")

    func testCombinesExactAuthorGenreAndExistingSearchWithoutDuplicatingCopies() {
        let match = BookEdition(title: "П’ять історій", author: "Валер’ян", isbn: "978-617-8076-41-2", genres: ["Історія", "Роман"])
        let another = BookEdition(title: "П’ять казок", author: "Валер’ян", genres: ["Казка"])
        let otherAuthor = BookEdition(title: "П’ять віршів", author: "Валер’ян Інший", genres: ["Роман"])
        let place = StorageLocation(name: "Дім")
        let snapshot = LibrarySnapshot(editions: [another, match, otherAuthor], copies: [BookCopy(editionID: match.id, locationID: place.id), BookCopy(editionID: match.id, locationID: place.id)], locations: [place])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, query: "п'ять", author: .value(" валер'ЯН "), genre: .value(" роман "), locale: uk), [match])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, query: "9786178076412", locale: uk), [match])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, author: .value("Валер"), locale: uk), [])
    }

    func testMissingFiltersDoNotCollideWithRealAuthorOrGenreNamedMissing() {
        let missing = BookEdition(title: "А", author: " \n")
        let named = BookEdition(title: "Б", author: "Автор не указан", genres: ["Без жанра"])
        let snapshot = LibrarySnapshot(editions: [named, missing])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, author: .missing, genre: .missing, locale: uk), [missing])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, author: .value("Автор не указан"), genre: .value("Без жанра"), locale: uk), [named])
    }

    func testOptionsDeduplicateCaseAndApostrophesKeepSpellingAndSortInLocale() {
        let snapshot = LibrarySnapshot(editions: [
            BookEdition(title: "1", author: " Валер’ян ", genres: ["Роман", "Історія"]),
            BookEdition(title: "2", author: "валер'ян", genres: ["роман", "Їжа"]),
            BookEdition(title: "3", author: "Андрій", genres: ["Європа", "Ґрунт"]),
            BookEdition(title: "4", author: "  ")
        ])
        XCTAssertEqual(LibraryBrowse.authors(in: snapshot, locale: uk), ["Андрій", "Валер’ян"])
        XCTAssertEqual(LibraryBrowse.genres(in: snapshot, locale: uk), ["Ґрунт", "Європа", "Історія", "Їжа", "Роман"])
    }

    func testUkrainianTitleOrderAndDescendingUseLocaleAlphabet() {
        let titles = ["Йод", "Їжак", "Історія", "Ич", "Життя", "Єнот", "Ера", "Дім", "Ґрунт", "Гора"]
        let snapshot = LibrarySnapshot(editions: titles.map { BookEdition(title: $0) })
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, locale: uk).map(\.title), titles.reversed())
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, ascending: false, locale: uk).map(\.title), titles)
    }

    func testRussianAndEnglishSortingAreCaseInsensitive() {
        let russian = LibrarySnapshot(editions: ["Яблоко", "Букварь", "азбука"].map { BookEdition(title: $0) })
        XCTAssertEqual(LibraryBrowse.editions(in: russian, locale: Locale(identifier: "ru_RU")).map(\.title), ["азбука", "Букварь", "Яблоко"])
        let english = LibrarySnapshot(editions: ["Zebra", "banana", "Apple"].map { BookEdition(title: $0) })
        XCTAssertEqual(LibraryBrowse.editions(in: english, locale: Locale(identifier: "en_US")).map(\.title), ["Apple", "banana", "Zebra"])
    }

    func testEquivalentTitlesHaveStableIdentifierOrderInBothDirections() {
        let first = BookEdition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "книга")
        let second = BookEdition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Книга")
        let snapshot = LibrarySnapshot(editions: [second, first])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, locale: uk), [first, second])
        XCTAssertEqual(LibraryBrowse.editions(in: snapshot, ascending: false, locale: uk), [first, second])
    }

    func testFiltersKeepUkrainianAndRussianLettersDistinct() {
        let names = ["Євген", "Евген", "Іван", "Їван", "Йван", "Иван", "Ґор", "Гор"]
        let snapshot = LibrarySnapshot(editions: names.map { BookEdition(title: $0, author: $0, genres: [$0]) })
        XCTAssertEqual(LibraryBrowse.authors(in: snapshot, locale: uk).count, names.count)
        XCTAssertEqual(LibraryBrowse.genres(in: snapshot, locale: uk).count, names.count)
        for name in names {
            XCTAssertEqual(LibraryBrowse.editions(in: snapshot, author: .value(name.lowercased()), genre: .value(name.uppercased()), locale: uk).map(\.title), [name])
        }
    }
}
