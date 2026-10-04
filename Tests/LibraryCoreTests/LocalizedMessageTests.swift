import XCTest
@testable import LibraryCore

final class LocalizedMessageTests: XCTestCase {
    func testInterpolationSeparatesTranslationKeyFromUserData() {
        let message: LocalizedMessage = "Книг: \(3), автор: \("Іван {0}")"
        XCTAssertEqual(message.key, "Книг: {0}, автор: {1}")
        XCTAssertEqual(message.rendered(template: "Author: {1}; books: {0}"), "Author: Іван {0}; books: 3")
    }

    func testRepeatedArgumentsAndLiteralPercentArePreserved() {
        let message: LocalizedMessage = "Значение: \("50%")"
        XCTAssertEqual(message.rendered(template: "{0} + {0} = 100%"), "50% + 50% = 100%")
    }

    func testFallbackRendersSourceTemplate() {
        let message: LocalizedMessage = "Выдано: \(2)"
        XCTAssertEqual(message.rendered(), "Выдано: 2")
    }

    func testVerbatimContentDoesNotBecomeATemplate() {
        let message = LocalizedMessage.verbatim("Моя книга {0} {1}")
        XCTAssertEqual(message.rendered(), "Моя книга {0} {1}")
    }
}
