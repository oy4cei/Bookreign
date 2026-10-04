import Foundation
import XCTest
@testable import LibraryCore

final class BookMetadataMergeTests: XCTestCase {
    func testFillsGeneratedEditionAndKeepsItsIdentity() {
        let id = UUID()
        let stored = BookEdition(
            id: id, title: "Книга · 978-966 4481974", isbn: "9789664481974",
            notes: "Данные издания нужно заполнить."
        )
        let incoming = BookEdition(
            title: "Малюк чує звук", author: "Саша Кольцова", isbn: "978-966-448-197-4",
            language: "uk", publisher: "Видавництво", year: "2023",
            coverURL: "https://example.test/cover.jpg"
        )

        XCTAssertTrue(stored.hasPlaceholderTitle)
        let result = stored.fillingMissingMetadata(from: incoming)
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.title, "Малюк чує звук")
        XCTAssertEqual(result.author, "Саша Кольцова")
        XCTAssertEqual(result.isbn, "9789664481974")
        XCTAssertEqual(result.language, "uk")
        XCTAssertEqual(result.publisher, "Видавництво")
        XCTAssertEqual(result.year, "2023")
        XCTAssertEqual(result.coverURL, "https://example.test/cover.jpg")
        XCTAssertEqual(result.notes, "")
    }

    func testKeepsUserEditsAndOwnCover() {
        let cover = Data([1, 2, 3])
        let stored = BookEdition(
            title: "Моя назва", author: "Мій автор", isbn: "9789664481974",
            language: "ru", publisher: "Моє видавництво", year: "2020",
            coverURL: "https://example.test/mine.jpg", coverData: cover,
            notes: "Мої нотатки"
        )
        let incoming = BookEdition(
            title: "Малюк чує звук", author: "Саша Кольцова", isbn: "9789664481974",
            language: "uk", publisher: "Інше", year: "2023",
            coverURL: "https://example.test/catalog.jpg", coverData: Data([9]),
            notes: "Catalog note"
        )

        XCTAssertFalse(stored.hasPlaceholderTitle)
        XCTAssertEqual(stored.fillingMissingMetadata(from: incoming), stored)
    }

    func testOnlyExactSameISBNPlaceholderCanBeReplaced() {
        let incoming = BookEdition(title: "Real title", author: "Author", isbn: "9789664481974")
        let unrelatedNumber = BookEdition(title: "Книга · 9789664481974, том 2", isbn: "9789664481974")
        let otherISBN = BookEdition(title: "Книга · 9789664481975", isbn: "9789664481974")
        let wrongCatalogBook = BookEdition(title: "Other book", author: "Other", isbn: "9789664481975")

        XCTAssertFalse(unrelatedNumber.hasPlaceholderTitle)
        XCTAssertFalse(otherISBN.hasPlaceholderTitle)
        XCTAssertEqual(unrelatedNumber.fillingMissingMetadata(from: incoming).title, unrelatedNumber.title)
        XCTAssertEqual(otherISBN.fillingMissingMetadata(from: incoming).title, otherISBN.title)
        let stored = BookEdition(title: "Книга · 9789664481974", isbn: "9789664481974")
        XCTAssertEqual(stored.fillingMissingMetadata(from: wrongCatalogBook), stored)
    }

    func testBlankFieldsFillWithoutOverwritingCustomNotesOrAddingUnsupportedLanguage() {
        let stored = BookEdition(
            title: "  ", author: "\n", isbn: "", language: "other",
            publisher: " ", year: "", coverURL: "", notes: "Personal note"
        )
        let incoming = BookEdition(
            title: "Книга", author: "Автор", isbn: "9781234567890",
            language: "de", publisher: "Publisher", year: "2023",
            coverURL: "https://example.test/cover.jpg"
        )

        let result = stored.fillingMissingMetadata(from: incoming)
        XCTAssertEqual(result.title, "Книга")
        XCTAssertEqual(result.author, "Автор")
        XCTAssertEqual(result.isbn, "9781234567890")
        XCTAssertEqual(result.language, "other")
        XCTAssertEqual(result.publisher, "Publisher")
        XCTAssertEqual(result.year, "2023")
        XCTAssertEqual(result.coverURL, "https://example.test/cover.jpg")
        XCTAssertEqual(result.notes, "Personal note")
    }

    func testValidISBN10AndISBN13MatchWithoutChangingStoredISBN() {
        let stored = BookEdition(title: "Книга · 0306406152", isbn: "0-306-40615-2")
        let incoming = BookEdition(
            title: "A real title", author: "An author", isbn: "9780306406157", language: "en"
        )

        let result = stored.fillingMissingMetadata(from: incoming)
        XCTAssertEqual(result.title, "A real title")
        XCTAssertEqual(result.author, "An author")
        XCTAssertEqual(result.isbn, "0-306-40615-2")
        XCTAssertEqual(result.language, "en")

        let reverse = BookEdition(title: "Книга · 9780306406157", isbn: "9780306406157")
        XCTAssertEqual(reverse.fillingMissingMetadata(from: BookEdition(
            title: "A real title", isbn: "0306406152"
        )).title, "A real title")
    }

    func testInvalidISBN10CheckDigitDoesNotMatchISBN13() {
        let stored = BookEdition(title: "Книга · 0306406153", isbn: "0306406153")
        let incoming = BookEdition(title: "Wrong match", author: "Author", isbn: "9780306406157")

        XCTAssertEqual(stored.fillingMissingMetadata(from: incoming), stored)
    }

    func testPrefixedStoredISBNAllowsMetadataAndPlaceholderReplacement() {
        let incoming = BookEdition(
            title: "Малюк чує звук", author: "Саша Кольцова",
            isbn: "9789664481974", language: "uk"
        )
        for storedISBN in ["ISBN 9789664481974", "ISBN: 9789664481974", "ISBN-13: 9789664481974"] {
            let stored = BookEdition(title: "Книга · \(storedISBN)", isbn: storedISBN)
            XCTAssertTrue(stored.hasPlaceholderTitle, storedISBN)
            let result = stored.fillingMissingMetadata(from: incoming)
            XCTAssertEqual(result.title, "Малюк чує звук", storedISBN)
            XCTAssertEqual(result.author, "Саша Кольцова", storedISBN)
            XCTAssertEqual(result.isbn, storedISBN)
        }

        let bareTitle = BookEdition(title: "Книга · 9789664481974", isbn: "ISBN-13: 9789664481974")
        XCTAssertTrue(bareTitle.hasPlaceholderTitle)
        XCTAssertEqual(bareTitle.fillingMissingMetadata(from: incoming).title, "Малюк чує звук")
    }
}
