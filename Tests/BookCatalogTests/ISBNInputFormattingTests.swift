import Foundation
import XCTest
@testable import BookCatalog

final class ISBNInputFormattingTests: XCTestCase {
    func testRequestedMaskAppearsProgressively() {
        let examples = [
            "": "", "9": "9", "978": "978", "9786": "978-6",
            "978617": "978-617", "9786178": "978-617-8",
            "9786178076": "978-617-8076", "97861780764": "978-617-8076-4",
            "978617807641": "978-617-8076-41", "9786178076412": "978-617-8076-41-2",
            "9791234567890": "979-123-4567-89-0"
        ]
        for (input, expected) in examples {
            XCTAssertEqual(ISBNInputFormatting.format(input), expected, input)
        }
    }

    func testPastedISBNLabelAndExistingSeparatorsAreNormalized() throws {
        let input = "ISBN-13: 978-617-8076-41-2"
        let result = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: "", range: NSRange(location: 0, length: 0), replacement: input))
        XCTAssertEqual(result.text, "978-617-8076-41-2")
        XCTAssertEqual(result.caretUTF16, result.text.utf16.count)
        XCTAssertEqual(ISBN.normalize(result.text), ISBN.normalize(input))
        XCTAssertEqual(ISBNInputFormatting.format(" ISBN 978 617 8076 41 2\n"), result.text)
    }

    func testISBN10WithXStaysUsable() {
        let input = "ISBN-10: 0-8044-2957-x"
        XCTAssertEqual(ISBNInputFormatting.format(input), "080442957X")
        XCTAssertEqual(ISBN.normalize(ISBNInputFormatting.format(input)), "080442957X")
    }

    func testExtraDigitsAndUnexpectedTextNeverBecomeAValidISBN() throws {
        let extraDigit = ISBNInputFormatting.format("97861780764123")
        XCTAssertEqual(extraDigit.filter(\.isNumber), "97861780764123")
        XCTAssertNil(ISBN.normalize(extraDigit))
        let unexpected = "book 9786178076412"
        XCTAssertEqual(ISBNInputFormatting.format(unexpected), unexpected)
        let result = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: "", range: NSRange(location: 0, length: 0), replacement: unexpected))
        XCTAssertEqual(result.text, unexpected)
        XCTAssertNil(ISBN.normalize(result.text))
        XCTAssertEqual(result.caretUTF16, unexpected.utf16.count)
    }

    func testTypingAcrossSeparatorKeepsCaretAfterInsertedDigit() throws {
        let result = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: "978", range: NSRange(location: 3, length: 0), replacement: "6"))
        XCTAssertEqual(result.text, "978-6")
        XCTAssertEqual(result.caretUTF16, 5)
    }

    func testBackspaceOnHyphenDeletesPrecedingDigit() throws {
        let result = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: "978-617-8076-41-2", range: NSRange(location: 7, length: 1), replacement: ""))
        XCTAssertEqual(result.text, "978-618-0764-12")
        XCTAssertEqual(result.caretUTF16, 6)
        let restored = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: result.text, range: NSRange(location: result.caretUTF16, length: 0), replacement: "7"))
        XCTAssertEqual(restored.text, "978-617-8076-41-2")
    }

    func testMiddleReplacementPreservesSuffixAndCaret() throws {
        let result = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: "978-617-8076-41-2", range: NSRange(location: 8, length: 4), replacement: "1234"))
        XCTAssertEqual(result.text, "978-617-1234-41-2")
        XCTAssertEqual(result.caretUTF16, 12)
    }

    func testReplacingAllAndDeletingAll() throws {
        let original = "978-617-8076-41-2"
        let replaced = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: original, range: NSRange(location: 0, length: original.utf16.count), replacement: "ISBN 0-8044-2957-X"))
        XCTAssertEqual(replaced.text, "080442957X")
        XCTAssertEqual(replaced.caretUTF16, 10)
        let deleted = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: original, range: NSRange(location: 0, length: original.utf16.count), replacement: ""))
        XCTAssertEqual(deleted.text, "")
        XCTAssertEqual(deleted.caretUTF16, 0)
    }

    func testInvalidUTF16RangesAreRejectedAndUnicodeInputIsPreserved() throws {
        XCTAssertNil(ISBNInputFormatting.applyingEdit(to: "978", range: NSRange(location: 4, length: 0), replacement: "1"))
        XCTAssertNil(ISBNInputFormatting.applyingEdit(to: "📚978", range: NSRange(location: 1, length: 0), replacement: "1"))
        let result = try XCTUnwrap(ISBNInputFormatting.applyingEdit(to: "978", range: NSRange(location: 0, length: 0), replacement: "📚"))
        XCTAssertEqual(result.text, "📚978")
        XCTAssertEqual(result.caretUTF16, 2)
    }
}
