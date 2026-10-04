import Foundation

/// An editing mask, not publisher-registration hyphenation or ISBN validation.
/// The requested visual groups apply to 978/979 numbers; ISBN-10 remains compact.
public enum ISBNInputFormatting {
    public struct EditResult: Equatable, Sendable {
        public let text: String
        public let caretUTF16: Int
    }

    public static func format(_ raw: String) -> String {
        guard let parsed = parse(raw) else { return raw }
        return formatted(parsed.symbols)
    }

    /// Maps a UIKit edit and caret through inserted separators. Unexpected text is
    /// retained for validation instead of silently turning a bad paste into an ISBN.
    /// Returns nil only if the supplied UTF-16 range is not a valid String range.
    public static func applyingEdit(to text: String, range: NSRange, replacement: String) -> EditResult? {
        guard let originalRange = Range(range, in: text),
              (originalRange.lowerBound == text.endIndex || text.indices.contains(originalRange.lowerBound)),
              (originalRange.upperBound == text.endIndex || text.indices.contains(originalRange.upperBound)) else { return nil }
        var editRange = originalRange
        if replacement.isEmpty, text[originalRange] == "-", parse(text) != nil,
           originalRange.lowerBound > text.startIndex {
            let previous = text.index(before: originalRange.lowerBound)
            if isSymbol(text[previous]) {
                // A mask separator must not trap Backspace when it is regenerated.
                editRange = previous..<originalRange.upperBound
            }
        }
        let editLocation = NSRange(text.startIndex..<editRange.lowerBound, in: text).length
        let candidate = text.replacingCharacters(in: editRange, with: replacement)
        let rawCaret = editLocation + replacement.utf16.count
        guard let parsed = parse(candidate) else {
            return EditResult(text: candidate, caretUTF16: rawCaret)
        }
        let output = formatted(parsed.symbols)
        let precedingSymbols = parsed.endOffsets.filter { $0 <= rawCaret }.count
        var caret = 0
        var seen = 0
        for character in output {
            guard seen < precedingSymbols else { break }
            caret += character.utf16.count
            if isSymbol(character) { seen += 1 }
        }
        return EditResult(text: output, caretUTF16: caret)
    }

    private static func formatted(_ symbols: String) -> String {
        guard (symbols.hasPrefix("978") || symbols.hasPrefix("979")),
              symbols.allSatisfy(isDigit) else { return symbols }
        let boundaries: Set<Int> = [3, 6, 10, 12]
        var output = ""
        for (index, character) in symbols.enumerated() {
            if boundaries.contains(index) { output.append("-") }
            output.append(character)
        }
        return output
    }

    private static func parse(_ raw: String) -> (symbols: String, endOffsets: [Int])? {
        var lower = raw.startIndex
        var upper = raw.endIndex
        while lower < upper, raw[lower].isWhitespace { lower = raw.index(after: lower) }
        while lower < upper, raw[raw.index(before: upper)].isWhitespace { upper = raw.index(before: upper) }
        if raw[lower..<upper].prefix(4).uppercased() == "ISBN" {
            lower = raw.index(lower, offsetBy: 4)
            let body = raw[lower..<upper]
            if body.hasPrefix("-10") || body.hasPrefix("-13") { lower = raw.index(lower, offsetBy: 3) }
            while lower < upper, " :#".contains(raw[lower]) { lower = raw.index(after: lower) }
            while lower < upper, " :#".contains(raw[raw.index(before: upper)]) { upper = raw.index(before: upper) }
        }
        var symbols = ""
        var endOffsets: [Int] = []
        for index in raw[lower..<upper].indices {
            let character = raw[index]
            if isSymbol(character) {
                symbols.append(contentsOf: String(character).uppercased())
                endOffsets.append(NSRange(raw.startIndex..<raw.index(after: index), in: raw).length)
            } else if character != "-" && !character.isWhitespace {
                return nil
            }
        }
        return (symbols, endOffsets)
    }

    private static func isSymbol(_ character: Character) -> Bool {
        isDigit(character) || character == "X" || character == "x"
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character >= "0" && character <= "9"
    }
}
