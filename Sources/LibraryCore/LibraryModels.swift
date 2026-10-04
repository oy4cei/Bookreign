import Foundation

public struct BookEdition: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var author: String
    public var isbn: String
    public var language: String
    public var publisher: String
    public var year: String
    public var coverURL: String
    public var coverData: Data?
    public var notes: String
    public var genres: [String] {
        didSet { genres = Self.normalizedGenres(genres) }
    }

    public init(
        id: UUID = UUID(), title: String, author: String = "", isbn: String = "",
        language: String = "other", publisher: String = "", year: String = "",
        coverURL: String = "", coverData: Data? = nil, notes: String = "", genres: [String] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.isbn = isbn
        self.language = language
        self.publisher = publisher
        self.year = year
        self.coverURL = coverURL
        self.coverData = coverData
        self.notes = notes
        self.genres = Self.normalizedGenres(genres)
    }

    /// Keeps the first spelling of each nonempty genre, without folding distinct letters.
    public static func normalizedGenres(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  seen.insert(LibrarySnapshot.normalizedSearchText(trimmed)).inserted else { return nil }
            return trimmed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, isbn, language, publisher, year, coverURL, coverData, notes, genres
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Only the newly introduced field may be absent in older databases/backups.
        // Keep all previously required fields strict so corrupt data is still reported.
        let genres = try values.contains(.genres) ? values.decode([String].self, forKey: .genres) : []
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            title: try values.decode(String.self, forKey: .title),
            author: try values.decode(String.self, forKey: .author),
            isbn: try values.decode(String.self, forKey: .isbn),
            language: try values.decode(String.self, forKey: .language),
            publisher: try values.decode(String.self, forKey: .publisher),
            year: try values.decode(String.self, forKey: .year),
            coverURL: try values.decode(String.self, forKey: .coverURL),
            coverData: try values.decodeIfPresent(Data.self, forKey: .coverData),
            notes: try values.decode(String.self, forKey: .notes),
            genres: genres
        )
    }
}

public struct BookCopy: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var editionID: UUID
    public var locationID: UUID
    public var shelf: String
    public var addedAt: Date

    public init(id: UUID = UUID(), editionID: UUID, locationID: UUID, shelf: String = "", addedAt: Date = Date()) {
        self.id = id
        self.editionID = editionID
        self.locationID = locationID
        self.shelf = shelf
        self.addedAt = addedAt
    }
}

public struct StorageLocation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String

    public init(id: UUID = UUID(), name: String, symbol: String = "house") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

public struct BookLoan: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var copyID: UUID
    public var borrower: String
    public var loanedAt: Date
    public var dueAt: Date?
    public var returnedAt: Date?

    public init(
        id: UUID = UUID(), copyID: UUID, borrower: String,
        loanedAt: Date = Date(), dueAt: Date? = nil, returnedAt: Date? = nil
    ) {
        self.id = id
        self.copyID = copyID
        self.borrower = borrower
        self.loanedAt = loanedAt
        self.dueAt = dueAt
        self.returnedAt = returnedAt
    }
}

public enum LibraryDataError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .unsupportedVersion(let version): return "Неподдерживаемая версия данных: \(version)"
        }
    }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var editions: [BookEdition]
    public var copies: [BookCopy]
    public var locations: [StorageLocation]
    public var loans: [BookLoan]

    public init(
        editions: [BookEdition] = [], copies: [BookCopy] = [],
        locations: [StorageLocation] = [], loans: [BookLoan] = []
    ) {
        self.editions = editions
        self.copies = copies
        self.locations = locations
        self.loans = loans
    }

    public static var empty: Self {
        Self(locations: [
            StorageLocation(name: "Дом", symbol: "house"),
            StorageLocation(name: "Дача", symbol: "tree")
        ])
    }

    public func validate() throws {
        guard !locations.isEmpty else {
            throw LibraryDataError.invalid("В библиотеке должно быть хотя бы одно место")
        }
        let allIDs = editions.map(\.id) + copies.map(\.id) + locations.map(\.id) + loans.map(\.id)
        guard Set(allIDs).count == allIDs.count else {
            throw LibraryDataError.invalid("Повторяется идентификатор записи")
        }
        guard editions.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LibraryDataError.invalid("У книги должно быть название")
        }
        let supportedLanguages: Set<String> = ["uk", "ru", "en", "other"]
        guard editions.allSatisfy({ supportedLanguages.contains($0.language) }) else {
            throw LibraryDataError.invalid("Неизвестный язык издания")
        }
        guard locations.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LibraryDataError.invalid("У места должно быть название")
        }
        let editionIDs = Set(editions.map(\.id))
        let locationIDs = Set(locations.map(\.id))
        guard copies.allSatisfy({ editionIDs.contains($0.editionID) && locationIDs.contains($0.locationID) }) else {
            throw LibraryDataError.invalid("Экземпляр ссылается на отсутствующую книгу или место")
        }
        let copyIDs = Set(copies.map(\.id))
        var activeCopyIDs = Set<UUID>()
        for loan in loans {
            guard copyIDs.contains(loan.copyID) else {
                throw LibraryDataError.invalid("Выдача ссылается на отсутствующий экземпляр")
            }
            guard !loan.borrower.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryDataError.invalid("У выдачи должен быть получатель")
            }
            guard loan.dueAt.map({ $0 >= loan.loanedAt }) ?? true,
                  loan.returnedAt.map({ $0 >= loan.loanedAt }) ?? true else {
                throw LibraryDataError.invalid("Дата выдачи позже срока или возврата")
            }
            if loan.returnedAt == nil && !activeCopyIDs.insert(loan.copyID).inserted {
                throw LibraryDataError.invalid("Экземпляр уже выдан")
            }
        }
    }

    public func matches(_ edition: BookEdition, query: String) -> Bool {
        let needle = Self.normalizedSearchText(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        if [edition.title, edition.author, edition.isbn].contains(where: {
            Self.normalizedSearchText($0).contains(needle)
        }) { return true }
        let isbnNeedle = needle.filter(\.isNumber)
        return !isbnNeedle.isEmpty
            && needle.allSatisfy { $0.isNumber || $0 == "-" || $0.isWhitespace }
            && edition.isbn.filter(\.isNumber).contains(isbnNeedle)
    }

    public func activeLoan(for copyID: UUID) -> BookLoan? {
        loans.first { $0.copyID == copyID && $0.returnedAt == nil }
    }

    static func normalizedSearchText(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "´", with: "'")
    }
}
