import Foundation
import XCTest
@testable import BookCatalog

final class GenreMetadataTests: XCTestCase {
    func testEditionUsesExplicitGenresAndOnlyRecognizedSubjectGenres() async throws {
        let client = genreClient(editionFields: #","genres":[" Juvenile literature. ","/tags/OL169T",""],"subjects":["Fantasy fiction","FANTASY FICTION","Foxes","London","Open Library Staff Picks","Fiction, historical","Поезія"]"#)
        let books = try await client.lookup(isbn: genreISBN)
        XCTAssertEqual(books.first?.genres, ["Juvenile literature.", "Fantasy fiction", "Поезія"])
    }

    func testLookupReadsAtMostOneWorkWhenEditionHasNoGenres() async throws {
        let client = genreClient(
            editionFields: #","works":[{"key":"/works/OL42W"},{"key":"/works/OL43W"}]"#,
            work: #"{"genres":["/tags/OL169T"],"subjects":["Foxes","Children's fiction","Fantasy fiction"]}"#
        )
        let books = try await client.lookup(isbn: genreISBN)
        XCTAssertEqual(books.first?.genres, ["Children's fiction", "Fantasy fiction"])
    }

    func testEditionGenresAvoidOptionalWorkRequest() async throws {
        let client = genreClient(editionFields: #","genres":["Poetry"],"works":[{"key":"/works/OL42W"}]"#)
        let books = try await client.lookup(isbn: genreISBN)
        XCTAssertEqual(books.first?.genres, ["Poetry"])
    }

    func testMissingAndMalformedGenresDoNotDiscardEdition() async throws {
        for fields in ["", #","genres":{},"subjects":false,"works":"invalid""#,
                       #","genres":[null,{},42,"Poetry"],"subjects":["London",{},"Drama"]"#] {
            let books = try await genreClient(editionFields: fields).lookup(isbn: genreISBN)
            XCTAssertEqual(books.first?.title, "Test edition")
            XCTAssertEqual(books.first?.genres, fields.contains("Poetry") ? ["Poetry", "Drama"] : [])
        }
    }

    func testMissingFailedAndMalformedWorkMetadataKeepISBNResult() async throws {
        for (status, body) in [(404, ""), (503, ""), (200, "not JSON"), (200, #"{"subjects":{}}"#)] {
            let client = genreClient(editionFields: #","works":[{"key":"/works/OL42W"}]"#,
                                     work: body, workStatus: status)
            let books = try await client.lookup(isbn: genreISBN)
            XCTAssertEqual(books.first?.title, "Test edition")
            XCTAssertEqual(books.first?.genres, [])
        }
    }

    func testUnsafeWorkKeyDoesNotTriggerRequest() async throws {
        let client = genreClient(editionFields: #","works":[{"key":"/works/../../accounts/private"}]"#)
        let books = try await client.lookup(isbn: genreISBN)
        XCTAssertEqual(books.first?.title, "Test edition")
        XCTAssertEqual(books.first?.genres, [])
    }

    func testOptionalWorkCancellationCancelsLookup() async throws {
        let client = genreClient(editionFields: #","works":[{"key":"/works/OL42W"}]"#, cancelWork: true)
        do {
            _ = try await client.lookup(isbn: genreISBN)
            XCTFail("Cancelled metadata request must not return a partial book")
        } catch is CancellationError {}
    }

    func testSearchUsesSubjectsWithoutAdditionalRequestsAndToleratesMalformedValues() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/search.json")
            let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "fields" }?.value
            XCTAssertTrue(fields?.split(separator: ",").contains("subject") == true)
            let body = #"{"docs":[{"key":"/works/OL42W","title":"Book one","subject":["Humorous stories","London",null,"Fantasy fiction"]},{"key":"/works/OL43W","title":"Book two","subject":{}},{"key":"/works/OL44W","title":"Book three"}]}"#
            return genreResponse(body, url: url)
        })
        let books = try await client.search("Book")
        XCTAssertEqual(books.map(\.genres), [["Humorous stories", "Fantasy fiction"], [], []])
    }

    func testMBooksUsesVerifiedCatalogCategoriesAndDecodesEntities() async throws {
        let fields = #","main_category":{"title":" Поезія &amp; проза "},"additional_categories":[{"title":"Поезія &amp; проза"},{"title":"Поезія для дітей"},{"title":""},{"other":"missing title"},null]"#
        let books = try await mbooksGenreClient(fields: fields).lookup(isbn: genreISBN)
        XCTAssertEqual(books.first?.genres, ["Поезія & проза", "Поезія для дітей"])
    }

    func testMissingAndMalformedMBooksCategoriesDoNotDiscardVerifiedISBN() async throws {
        for fields in ["", #","main_category":false,"additional_categories":{}"#] {
            let books = try await mbooksGenreClient(fields: fields).lookup(isbn: genreISBN)
            XCTAssertEqual(books.first?.title, "Каталог")
            XCTAssertEqual(books.first?.genres, [])
        }
    }
}

private let genreISBN = "9780306406157"

private func genreClient(editionFields: String, work: String? = nil, workStatus: Int = 200, cancelWork: Bool = false) -> CatalogClient {
    CatalogClient(fetch: { request in
        let url = try XCTUnwrap(request.url)
        switch url.path {
        case "/isbn/\(genreISBN).json":
            return genreResponse(#"{"key":"/books/OL42M","title":"Test edition","languages":[{"key":"/languages/ukr"}]"# + editionFields + "}", url: url)
        case "/works/OL42W.json":
            if cancelWork { throw URLError(.cancelled) }
            let body = try XCTUnwrap(work, "Must not request work metadata when edition genres are present")
            XCTAssertEqual(request.timeoutInterval, 5)
            return genreResponse(body, url: url, status: workStatus)
        default:
            XCTFail("Unexpected request \(url)")
            throw CatalogError.invalidResponse
        }
    })
}

private func mbooksGenreClient(fields: String) -> CatalogClient {
    CatalogClient(fetch: { request in
        let url = try XCTUnwrap(request.url)
        switch (url.host, url.path) {
        case ("openlibrary.org", _): return genreResponse("", url: url, status: 404)
        case ("api.mbooks.com.ua", "/api/v1/search/main"):
            return genreResponse(#"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"book"}],"total":1}}}}"#, url: url)
        case ("api.mbooks.com.ua", "/api/v1/books/book"):
            let body = #"{"status":"success","code":200,"data":{"item":{"slug":"book","title":"Каталог","isbn":"9780306406157","languages":["Українська"],"authors":[]"# + fields + "}}}"
            return genreResponse(body, url: url)
        default: XCTFail("Unexpected request \(url)"); throw CatalogError.invalidResponse
        }
    })
}

private func genreResponse(_ body: String, url: URL, status: Int = 200) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
}
