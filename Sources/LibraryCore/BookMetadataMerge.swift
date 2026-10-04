import Foundation

public extension BookEdition {
    /// Whether the title is the generated ISBN label for this edition.
    var hasPlaceholderTitle: Bool {
        Self.isPlaceholderTitle(title, for: isbn)
    }

    /// Adds catalog details to an edition without replacing its saved edits or identity.
    func fillingMissingMetadata(from incoming: BookEdition) -> BookEdition {
        let storedISBN = Self.normalizedISBN(isbn)
        let incomingISBN = Self.normalizedISBN(incoming.isbn)
        if !Self.isBlank(isbn) && !Self.isBlank(incoming.isbn) {
            guard let storedISBN, let incomingISBN,
                  Self.isSameISBN(storedISBN, incomingISBN) else { return self }
        }

        var result = self
        if Self.isBlank(result.isbn), incomingISBN != nil {
            result.isbn = incoming.isbn
        }

        let meaningfulIncomingTitle = !Self.isBlank(incoming.title)
            && !Self.isPlaceholderTitle(incoming.title, for: incoming.isbn)
        if (Self.isBlank(result.title) || Self.isPlaceholderTitle(result.title, for: result.isbn))
            && meaningfulIncomingTitle {
            result.title = incoming.title
        }
        if Self.isBlank(result.author) && !Self.isBlank(incoming.author) {
            result.author = incoming.author
        }
        if Self.isBlank(result.publisher) && !Self.isBlank(incoming.publisher) {
            result.publisher = incoming.publisher
        }
        if Self.isBlank(result.year) && !Self.isBlank(incoming.year) {
            result.year = incoming.year
        }
        if Self.isBlank(result.coverURL) && !Self.isBlank(incoming.coverURL) {
            result.coverURL = incoming.coverURL
        }
        if result.genres.isEmpty {
            result.genres = incoming.genres
        }
        if result.language == "other" && ["uk", "ru", "en"].contains(incoming.language) {
            result.language = incoming.language
        }
        if result.notes == "Данные издания нужно заполнить."
            && meaningfulIncomingTitle && !Self.isBlank(incoming.author)
            && !Self.isBlank(result.title) && !Self.isBlank(result.author) {
            result.notes = ""
        }
        return result
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isPlaceholderTitle(_ title: String, for isbn: String) -> Bool {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Книга · "
        guard label.hasPrefix(prefix), let expectedISBN = normalizedISBN(isbn) else { return false }
        let titleISBN = String(label.dropFirst(prefix.count))
        return normalizedISBN(titleISBN) == expectedISBN
    }

    private static func normalizedISBN(_ value: String) -> String? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.uppercased().hasPrefix("ISBN") {
            value = String(value.dropFirst(4))
            if value.hasPrefix("-10") || value.hasPrefix("-13") {
                value = String(value.dropFirst(3))
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " :#"))
        }
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 48...57, 88: result.append(String(scalar))
            case 120: result.append("X")
            case 45: continue
            default:
                guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { return nil }
            }
        }
        guard result.unicodeScalars.contains(where: { (48...57).contains($0.value) }) else { return nil }
        return result
    }

    private static func isSameISBN(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        guard let firstCanonical = canonicalISBN(first),
              let secondCanonical = canonicalISBN(second) else { return false }
        return firstCanonical == secondCanonical
    }

    private static func canonicalISBN(_ value: String) -> String? {
        let bytes = Array(value.utf8)
        if bytes.count == 13 {
            guard bytes.allSatisfy({ (48...57).contains($0) }),
                  isbn13CheckDigit(for: Array(bytes.prefix(12))) == bytes[12] else { return nil }
            return value
        }
        guard bytes.count == 10,
              bytes.prefix(9).allSatisfy({ (48...57).contains($0) }),
              (48...57).contains(bytes[9]) || bytes[9] == 88 else { return nil }

        let checkDigit = bytes[9] == 88 ? 10 : Int(bytes[9] - 48)
        let checksum = (0..<9).reduce(0) { $0 + (10 - $1) * Int(bytes[$1] - 48) } + checkDigit
        guard checksum.isMultiple(of: 11) else { return nil }

        let base = "978" + String(value.prefix(9))
        let check = isbn13CheckDigit(for: Array(base.utf8))
        return base + String(UnicodeScalar(check))
    }

    private static func isbn13CheckDigit(for firstTwelve: [UInt8]) -> UInt8 {
        let sum = firstTwelve.enumerated().reduce(0) { total, entry in
            total + Int(entry.element - 48) * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return UInt8((10 - sum % 10) % 10) + 48
    }
}
