import Foundation
import XCTest
@testable import BookCatalog

final class CoverSearchTests: XCTestCase {
    func testCoverCandidatesRequireHTTPSAndDeduplicateImageURLs() {
        let books = [
            CatalogBook(id: "first", title: "Book", coverURL: " https://covers.example.org/book.jpg "),
            CatalogBook(id: "duplicate", title: "Other edition", coverURL: "https://covers.example.org/book.jpg"),
            CatalogBook(id: "insecure", title: "HTTP", coverURL: "http://covers.example.org/book.jpg"),
            CatalogBook(id: "missing", title: "Missing"),
            CatalogBook(id: "credentials", title: "Credentials", coverURL: "https://user:pass@covers.example.org/a.jpg"),
            CatalogBook(id: "second", title: "Second", coverURL: "https://covers.example.org/second.png")
        ]
        XCTAssertEqual(CoverSearch.candidates(from: books).map(\.id), ["first", "second"])
        XCTAssertEqual(CoverSearch.candidates(from: books).first?.coverURL, "https://covers.example.org/book.jpg")
    }

    func testImageURLRequiresHostAndRejectsNonHTTPSSchemes() {
        for value in ["", "file:///tmp/book.jpg", "data:image/png;base64,AAA", "https:///", "https://", "https://user@example.org/a.jpg"] {
            XCTAssertNil(CoverSearch.imageURL(value), value)
        }
        XCTAssertEqual(CoverSearch.imageURL(" https://example.org/обложка.jpg ")?.host, "example.org")
    }

    func testSearchLinksEncodeUserQueryWithoutChangingItsMeaning() throws {
        let query = "Лісова пісня & ISBN 978-617-8076-41-2"
        let url = try XCTUnwrap(CoverSearch.webSearchURL(query: query))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "https")
        XCTAssertEqual(parts.host, "www.google.com")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "q" }?.value, query)
        XCTAssertEqual(parts.queryItems?.first { $0.name == "tbm" }?.value, "isch")
        XCTAssertNil(CoverSearch.webSearchURL(query: " \n "))
    }

    func testImageResponseRejectsErrorPagesWrongTypesAndOversizedPayloads() throws {
        let url = try XCTUnwrap(URL(string: "https://example.org/cover.jpg"))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg; charset=binary"])!
        XCTAssertNoThrow(try CoverSearch.validateImageResponse(response))
        for (status, type, length) in [(404, "image/jpeg", "12"), (200, "text/html", "12"), (200, "image/png", "12582913")] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type, "Content-Length": length])!
            XCTAssertThrowsError(try CoverSearch.validateImageResponse(response))
        }
        let insecure = HTTPURLResponse(url: URL(string: "http://example.org/cover.jpg")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!
        XCTAssertThrowsError(try CoverSearch.validateImageResponse(insecure))
    }
}
