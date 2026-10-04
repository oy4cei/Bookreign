import Foundation
import XCTest
@testable import BookCatalog

final class BookCatalogTests: XCTestCase {
    func testISBNNormalizesAndValidatesBothChecksums() {
        XCTAssertEqual(ISBN.normalize("ISBN 0-306-40615-2"), "0306406152")
        XCTAssertEqual(ISBN.normalize("978-0-306-40615-7"), "9780306406157")
        XCTAssertEqual(ISBN.normalize("0-8044-2957-X"), "080442957X")
        XCTAssertNil(ISBN.normalize("978-0-306-40615-8"))
        XCTAssertNil(ISBN.normalize("0-306-40615-3"))
        XCTAssertNil(ISBN.normalize("9780306406157-extra"))
    }

    func testISBNExtractFindsValidDistinctCodesOnly() {
        XCTAssertEqual(ISBN.extract(from: "Scan: ISBN 978-0-306-40615-7 and 0-8044-2957-X, then 9780306406158. Repeat 9780306406157."), ["9780306406157", "080442957X"])
    }

    func testCanonicalISBNMatchesTenAndThirteenDigitEditions() {
        XCTAssertEqual(ISBN.canonical("0385472579"), "9780385472579")
        XCTAssertEqual(ISBN.canonical("9780385472579"), "9780385472579")
        XCTAssertNil(ISBN.canonical("0385472578"))
    }

    func testCatalogErrorsHaveReadableLocalizedDescriptions() {
        XCTAssertTrue((CatalogError.invalidISBN as NSError).localizedDescription.contains("ISBN"))
        XCTAssertTrue((CatalogError.invalidResponse as NSError).localizedDescription.contains("відповід"))
        XCTAssertTrue((CatalogError.httpStatus(503) as NSError).localizedDescription.contains("503"))
    }

    func testLookupUsesEditionMetadataAndAuthorRecord() async throws {
        let client = CatalogClient(fetch: { request in
            XCTAssertEqual(request.timeoutInterval, 15)
            let path = try XCTUnwrap(request.url?.path)
            let body: String
            switch path {
            case "/isbn/9780306406157.json":
                body = #"{"key":"/books/OL42M","title":"Гарна книга","isbn_13":["9780306406157"],"publishers":["Книгарня"],"publish_date":"2019-05-04","languages":[{"key":"/languages/ukr"}],"covers":[1234],"authors":[{"key":"/authors/OL7A"}]}"#
            case "/authors/OL7A.json": body = #"{"name":"Авторка"}"#
            default: XCTFail("Unexpected path \(path)"); throw CatalogError.invalidResponse
            }
            return (Data(body.utf8), HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.lookup(isbn: "978-0-306-40615-7")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].id, "openlibrary:OL42M")
        XCTAssertEqual(books[0].author, "Авторка")
        XCTAssertEqual(books[0].language, "uk")
        XCTAssertEqual(books[0].publisher, "Книгарня")
        XCTAssertEqual(books[0].year, "2019")
        XCTAssertEqual(books[0].isbn, "9780306406157")
        XCTAssertEqual(books[0].coverURL, "https://covers.openlibrary.org/b/id/1234-M.jpg")
        XCTAssertEqual(books[0].sourceName, "Open Library")
        XCTAssertEqual(books[0].sourceURL, "https://openlibrary.org/books/OL42M")
    }

    func testLookupNotFoundIsEmptyButHTTPFailureThrows() async throws {
        let missing = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "openlibrary.org" {
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            XCTAssertEqual(url.host, "api.mbooks.com.ua")
            let body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[],"total":0}}}}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let missingBooks = try await missing.lookup(isbn: "9780306406157")
        XCTAssertTrue(missingBooks.isEmpty)
        let failing = CatalogClient(fetch: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await failing.lookup(isbn: "9780306406157")
            XCTFail("Expected service error")
        } catch let error as CatalogError {
            XCTAssertEqual(error, .httpStatus(503))
        }
    }

    func testLookupFallsBackToExactMBooksISBNAndUsesDetailMetadata() async throws {
        let isbn = "9789664481974"
        let slug = "447368-maliuk-chuie-zvuk"
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.timeoutInterval, 15)
            switch (url.host, url.path) {
            case ("openlibrary.org", "/isbn/9789664481974.json"):
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            case ("api.mbooks.com.ua", "/api/v1/search/main"):
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertTrue(query?.contains { $0.name == "query" && $0.value == isbn } == true)
                let body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"447368-maliuk-chuie-zvuk"}],"total":1}}}}"#
                return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            case ("api.mbooks.com.ua", "/api/v1/books/\(slug)"):
                let body = #"{"status":"success","code":200,"data":{"item":{"slug":"447368-maliuk-chuie-zvuk","title":"Малюк чує звук","isbn":"978-966-448-197-4","year":2023,"languages":["Українська"],"publisher":{"name":"Видавництво Старого Лева"},"authors":[{"first_name":"Саша","last_name":"Кольцова"}],"cover":{"front_cover":"https://s3.vcdn.biz/cover.jpeg"}}}}"#
                return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            default: XCTFail("Unexpected URL \(url), path=[\(url.path)]"); throw CatalogError.invalidResponse
            }
        })
        let books = try await client.lookup(isbn: isbn)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Малюк чує звук")
        XCTAssertEqual(books[0].author, "Саша Кольцова")
        XCTAssertEqual(books[0].language, "uk")
        XCTAssertEqual(books[0].publisher, "Видавництво Старого Лева")
        XCTAssertEqual(books[0].year, "2023")
        XCTAssertEqual(books[0].coverURL, "https://s3.vcdn.biz/cover.jpeg")
        XCTAssertEqual(books[0].sourceName, "MEGOGO BOOKS")
        XCTAssertEqual(books[0].sourceURL, "https://mbooks.com.ua/book/447368-maliuk-chuie-zvuk/")
    }

    func testFallbackGeneralizesToAnotherISBNAndDecodesTitleEntities() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            let body: String
            let status: Int
            switch (url.host, url.path) {
            case ("openlibrary.org", _): body = ""; status = 404
            case ("api.mbooks.com.ua", "/api/v1/search/main"):
                body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"897648-nad-chornym-morem"}],"total":1}}}}"#
                status = 200
            case ("api.mbooks.com.ua", "/api/v1/books/897648-nad-chornym-morem"):
                body = #"{"status":"success","code":200,"data":{"item":{"slug":"897648-nad-chornym-morem","title":"Над &quot;Чорним&quot; морем","isbn":"978-617-17-0486-2","year":2025,"languages":["Українська"],"publisher":{"name":"Vivat"},"authors":[{"first_name":"Іван","last_name":"Нечуй-Левицький"}],"cover":{"front_cover":"https://s9.vcdn.biz/cover.jpeg"}}}}"#
                status = 200
            default: XCTFail("Unexpected URL \(url), path=[\(url.path)]"); throw CatalogError.invalidResponse
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.lookup(isbn: "9786171704862")
        XCTAssertEqual(books.first?.title, "Над \"Чорним\" морем")
        XCTAssertEqual(books.first?.author, "Іван Нечуй-Левицький")
        XCTAssertEqual(books.first?.year, "2025")
    }

    func testISBN10FallbackSearchesEquivalentISBN13() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "openlibrary.org" {
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            let body: String
            if url.path == "/api/v1/search/main" {
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertTrue(query?.contains { $0.name == "query" && $0.value == "9786171704862" } == true)
                body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"897648-nad-chornym-morem"}],"total":1}}}}"#
            } else if url.path == "/api/v1/books/897648-nad-chornym-morem" {
                body = #"{"status":"success","code":200,"data":{"item":{"slug":"897648-nad-chornym-morem","title":"Над Чорним морем","isbn":"978-617-17-0486-2","languages":["Українська"],"authors":[]}}}"#
            } else {
                XCTFail("Unexpected URL \(url)")
                throw CatalogError.invalidResponse
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.lookup(isbn: "6171704865")
        XCTAssertEqual(books.first?.isbn, "9786171704862")
    }

    func testOpenLibraryFailureCanStillUseVerifiedFallback() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            let body: String
            let status: Int
            switch (url.host, url.path) {
            case ("openlibrary.org", _): body = ""; status = 503
            case ("api.mbooks.com.ua", "/api/v1/search/main"):
                body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"447368-maliuk-chuie-zvuk"}],"total":1}}}}"#
                status = 200
            case ("api.mbooks.com.ua", "/api/v1/books/447368-maliuk-chuie-zvuk"):
                body = #"{"status":"success","code":200,"data":{"item":{"slug":"447368-maliuk-chuie-zvuk","title":"Малюк чує звук","isbn":"978-966-448-197-4","languages":["Українська"],"authors":[]}}}"#
                status = 200
            default: throw CatalogError.invalidResponse
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.lookup(isbn: "9789664481974")
        XCTAssertEqual(books.first?.title, "Малюк чує звук")
    }

    func testOpenLibraryFailureAndEmptyFallbackReportsError() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "openlibrary.org" {
                return (Data(), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            }
            let body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[],"total":0}}}}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await client.lookup(isbn: "9789664481974")
            XCTFail("A failed primary source cannot be reported as a definitive miss")
        } catch let error as CatalogError {
            XCTAssertEqual(error, .httpStatus(503))
        }
    }

    func testFallbackRejectsSearchCandidateWithDifferentDetailISBN() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            let body: String
            let status: Int
            switch (url.host, url.path) {
            case ("openlibrary.org", _): body = ""; status = 404
            case ("api.mbooks.com.ua", "/api/v1/search/main"):
                body = #"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"wrong-book"}],"total":1}}}}"#
                status = 200
            case ("api.mbooks.com.ua", "/api/v1/books/wrong-book"):
                body = #"{"status":"success","code":200,"data":{"item":{"slug":"wrong-book","title":"Wrong book","isbn":"978-617-17-0486-2","languages":["Українська"],"authors":[]}}}"#
                status = 200
            default: XCTFail("Unexpected URL \(url), path=[\(url.path)]"); throw CatalogError.invalidResponse
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.lookup(isbn: "9789664481974")
        XCTAssertTrue(books.isEmpty)
    }

    func testMalformedFallbackResponseIsAnErrorNotNoMatch() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            let status = url.host == "openlibrary.org" ? 404 : 200
            return (Data(#"{"status":"success","data":{}}"#.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await client.lookup(isbn: "9789664481974")
            XCTFail("Expected malformed response error")
        } catch let error as CatalogError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testFallbackPropagatesCancellation() async throws {
        let client = CatalogClient(fetch: { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "openlibrary.org" {
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            throw CancellationError()
        })
        do {
            _ = try await client.lookup(isbn: "9789664481974")
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation must not be interpreted as a missing book.
        }
    }

    func testSearchUsesMatchingEditionFieldsWithoutBorrowingWorkISBN() async throws {
        let client = CatalogClient(fetch: { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/search.json")
            XCTAssertTrue(components.queryItems?.contains(where: { $0.name == "q" && $0.value == "Місто language:ukr" }) == true)
            let body = #"{"docs":[{"key":"/works/OL9W","title":"Other title","author_name":["Author"],"isbn":["9780306406157"],"editions":{"docs":[{"key":"/books/OL8M","title":"Місто","isbn":["080442957X"],"language":["ukr"],"publisher":["Видавець"],"publish_date":"2021","cover_i":999}]}},{"key":"/works/OL10W","title":"Слово","author_name":["Writer"],"isbn":["9780306406157"]}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.search("Місто", language: "uk")
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].title, "Місто")
        XCTAssertEqual(books[0].isbn, "080442957X")
        XCTAssertEqual(books[0].language, "uk")
        XCTAssertEqual(books[0].publisher, "Видавець")
        XCTAssertEqual(books[1].isbn, "")
        XCTAssertEqual(books[1].id, "openlibrary:OL10W")
    }

    func testSearchDoesNotClaimAnotherLanguageEditionAsRequestedBook() async throws {
        let client = CatalogClient(fetch: { request in
            let body = #"{"docs":[{"key":"/works/OL9W","title":"Місто","author_name":["Author"],"editions":{"docs":[{"key":"/books/OL8M","title":"Город","isbn":["080442957X"],"language":["rus"]}]}}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.search("Місто", language: "uk")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].id, "openlibrary:OL9W")
        XCTAssertEqual(books[0].title, "Місто")
        XCTAssertEqual(books[0].isbn, "")
    }

    func testSearchAcceptsOpenLibraryEditionPublishDateArray() async throws {
        let client = CatalogClient(fetch: { request in
            let body = #"{"docs":[{"key":"/works/OL999W","title":"Лісова пісня","author_name":["Леся Українка"],"editions":{"docs":[{"key":"/books/OL53666932M","language":["ukr"],"publish_date":["192u"],"publisher":["Ukraïnsʹka nakladni͡a"],"title":"Лісова пісня"}],"numFound":1,"numFoundExact":true,"start":0}}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let books = try await client.search("Лісова пісня", language: "uk")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Лісова пісня")
        XCTAssertEqual(books[0].language, "uk")
        XCTAssertEqual(books[0].publisher, "Ukraïnsʹka nakladni͡a")
        XCTAssertEqual(books[0].year, "")
    }
}
