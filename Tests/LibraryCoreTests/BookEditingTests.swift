import XCTest
@testable import LibraryCore

final class BookEditingTests: XCTestCase {
    func testSavingOpenEditorPreservesFieldsChangedByAnotherDevice() {
        let original = BookEdition(title: "Original", author: "Author", notes: "Note")
        var current = original
        current.author = "Corrected remotely"
        current.coverURL = "https://example.com/new.jpg"
        var edited = original
        edited.title = "Local title"
        let result = current.applyingEdits(edited, from: original)
        XCTAssertEqual(result.title, "Local title")
        XCTAssertEqual(result.author, "Corrected remotely")
        XCTAssertEqual(result.coverURL, "https://example.com/new.jpg")
    }
}
