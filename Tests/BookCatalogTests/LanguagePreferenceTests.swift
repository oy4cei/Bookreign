import Foundation
import XCTest
@testable import BookCatalog

final class LanguagePreferenceTests: XCTestCase {
    func testUkrainianRecordIsPreferredOverRussianOpenLibraryRecordForSameISBN() async throws {
        let client = try fixtureClient(openLibraryLanguage: "rus", books: [
            FixtureBook(slug: "uk-book", title: "Українська книга", language: "Українська")
        ])

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.map(\.language), ["uk", "ru"])
        XCTAssertEqual(books.map(\.title), ["Українська книга", "Русская книга"])
        XCTAssertEqual(books.first?.sourceName, "MEGOGO BOOKS")
        XCTAssertTrue(books.allSatisfy { ISBN.canonical($0.isbn) == fixtureISBN })
    }

    func testMBooksChecksLaterExactMatchesForUkrainianAndKeepsRussianAlternative() async throws {
        let client = try fixtureClient(books: [
            FixtureBook(slug: "ru-book", title: "Русская книга", language: "Російська"),
            FixtureBook(slug: "uk-book", title: "Українська книга", language: "Українська")
        ])

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.map(\.language), ["uk", "ru"])
        XCTAssertEqual(books.map(\.title), ["Українська книга", "Русская книга"])
    }

    func testRussianOnlyMetadataKeepsItsActualLanguageAndTitle() async throws {
        let client = try fixtureClient(openLibraryLanguage: "rus")

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.language, "ru")
        XCTAssertEqual(books.first?.title, "Русская книга")
    }

    func testOptionalProviderFailureDoesNotDiscardValidOpenLibraryResult() async throws {
        let client = try fixtureClient(openLibraryLanguage: "rus", failurePaths: ["/api/v1/search/main": 503])

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.id, "openlibrary:OL42M")
        XCTAssertEqual(books.first?.language, "ru")
    }

    func testOptionalProviderCancellationStillCancelsTheLookup() async throws {
        let client = try fixtureClient(openLibraryLanguage: "rus", cancelledPath: "/api/v1/search/main")

        do {
            _ = try await client.lookup(isbn: fixtureISBN)
            XCTFail("Cancellation must not return a partial result")
        } catch is CancellationError {
            // A dismissed search remains dismissed, even after one provider returned metadata.
        }
    }

    func testUkrainianRecordWithDifferentISBNCannotReplaceRussianMatch() async throws {
        let client = try fixtureClient(openLibraryLanguage: "rus", books: [
            FixtureBook(slug: "different-edition", title: "Інше видання", language: "Українська", isbn: "9786171704862")
        ])

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.language, "ru")
        XCTAssertEqual(books.first?.isbn, fixtureISBN)
    }

    func testMBooksKeepsVerifiedMatchIfAnotherCandidateFails() async throws {
        let client = try fixtureClient(books: [
            FixtureBook(slug: "ru-book", title: "Русская книга", language: "Російська"),
            FixtureBook(slug: "failed-book", title: "Українська книга", language: "Українська")
        ], failurePaths: ["/api/v1/books/failed-book": 503])

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.map(\.language), ["ru"])
    }

    func testMBooksContinuesPastFailedCandidateToFindUkrainianMatch() async throws {
        let client = try fixtureClient(books: [
            FixtureBook(slug: "failed-book", title: "Русская книга", language: "Російська"),
            FixtureBook(slug: "uk-book", title: "Українська книга", language: "Українська")
        ], failurePaths: ["/api/v1/books/failed-book": 503])

        let books = try await client.lookup(isbn: fixtureISBN)

        XCTAssertEqual(books.map(\.language), ["uk"])
    }

    func testExplicitRussianPreferenceOverridesDefaultWithoutChangingRecords() async throws {
        let client = try fixtureClient(books: [
            FixtureBook(slug: "uk-book", title: "Українська книга", language: "Українська"),
            FixtureBook(slug: "ru-book", title: "Русская книга", language: "Російська")
        ])

        let books = try await client.lookup(isbn: fixtureISBN, preferredLanguage: "ru")

        XCTAssertEqual(books.map(\.language), ["ru", "uk"])
        XCTAssertEqual(books.map(\.title), ["Русская книга", "Українська книга"])
    }

    func testMBooksCancellationAfterValidCandidateDoesNotReturnPartialMatch() async throws {
        let client = try fixtureClient(books: [
            FixtureBook(slug: "ru-book", title: "Русская книга", language: "Російська"),
            FixtureBook(slug: "uk-book", title: "Українська книга", language: "Українська")
        ], cancelledPath: "/api/v1/books/uk-book")

        do {
            _ = try await client.lookup(isbn: fixtureISBN)
            XCTFail("Cancellation must propagate even after a verified candidate")
        } catch is CancellationError {
            // Partial matches are only returned for actual provider failures, not cancellation.
        }
    }
}

private let fixtureISBN = "9789664481974"

private struct FixtureBook {
    let slug: String
    let title: String
    let language: String
    var isbn: String = fixtureISBN
}

private func fixtureClient(
    openLibraryLanguage: String? = nil,
    books: [FixtureBook] = [],
    failurePaths: [String: Int] = [:],
    cancelledPath: String? = nil
) throws -> CatalogClient {
    var bodies: [String: Data] = [:]
    if let openLibraryLanguage {
        bodies["/isbn/\(fixtureISBN).json"] = try JSONSerialization.data(withJSONObject: [
            "key": "/books/OL42M", "title": "Русская книга", "isbn_13": [fixtureISBN],
            "languages": [["key": "/languages/\(openLibraryLanguage)"]], "authors": []
        ])
    }
    bodies["/api/v1/search/main"] = try JSONSerialization.data(withJSONObject: [
        "status": "success", "code": 200,
        "data": ["items": ["books": ["items": books.map { ["slug": $0.slug] }, "total": books.count]]]
    ])
    for book in books {
        bodies["/api/v1/books/\(book.slug)"] = try JSONSerialization.data(withJSONObject: [
            "status": "success", "code": 200,
            "data": ["item": ["slug": book.slug, "title": book.title, "isbn": book.isbn,
                               "languages": [book.language], "authors": []]]
        ])
    }
    let responses = bodies
    return CatalogClient(fetch: { request in
        let url = try XCTUnwrap(request.url)
        if url.path == cancelledPath { throw URLError(.cancelled) }
        let status = failurePaths[url.path] ?? (responses[url.path] == nil ? 404 : 200)
        return (responses[url.path] ?? Data(), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    })
}
