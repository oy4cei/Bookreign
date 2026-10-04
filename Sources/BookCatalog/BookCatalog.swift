import Foundation

public struct CatalogBook: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var author: String
    public var isbn: String
    public var language: String
    public var publisher: String
    public var year: String
    public var coverURL: String
    public var sourceName: String
    public var sourceURL: String
    public var genres: [String]

    public init(
        id: String,
        title: String,
        author: String = "",
        isbn: String = "",
        language: String = "other",
        publisher: String = "",
        year: String = "",
        coverURL: String = "",
        sourceName: String = "",
        sourceURL: String = "",
        genres: [String] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.isbn = isbn
        self.language = language
        self.publisher = publisher
        self.year = year
        self.coverURL = coverURL
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.genres = genres
    }
}

public enum ISBN {
    /// Returns a valid ISBN as ISBN-13, so ISBN-10 and ISBN-13 labels on the same edition compare equally.
    public static func canonical(_ raw: String) -> String? {
        guard let code = normalize(raw) else { return nil }
        guard code.count == 10 else { return code }
        let stem = "978" + code.prefix(9)
        let sum = stem.enumerated().reduce(0) { total, entry in
            total + (Int(String(entry.element)) ?? 0) * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return stem + String((10 - sum % 10) % 10)
    }

    public static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.uppercased().hasPrefix("ISBN") {
            value = String(value.dropFirst(4))
            if value.hasPrefix("-10") || value.hasPrefix("-13") { value = String(value.dropFirst(3)) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " :#"))
        }
        guard !value.isEmpty, value.allSatisfy({ $0.isASCIIDigit || $0 == "-" || $0.isWhitespace || $0 == "X" || $0 == "x" }) else { return nil }
        let code = value.filter { $0.isASCIIDigit || $0 == "X" || $0 == "x" }.uppercased()
        let digits = Array(code)
        if digits.count == 10 {
            guard digits.dropLast().allSatisfy(\.isASCIIDigit) else { return nil }
            let sum = digits.enumerated().reduce(0) { total, entry in
                let value = entry.element == "X" ? 10 : Int(String(entry.element)) ?? 0
                return total + (10 - entry.offset) * value
            }
            return sum % 11 == 0 ? code : nil
        }
        if digits.count == 13 {
            guard digits.allSatisfy(\.isASCIIDigit), code.hasPrefix("978") || code.hasPrefix("979") else { return nil }
            let sum = digits.enumerated().reduce(0) { total, entry in
                total + (Int(String(entry.element)) ?? 0) * (entry.offset.isMultiple(of: 2) ? 1 : 3)
            }
            return sum % 10 == 0 ? code : nil
        }
        return nil
    }

    public static func extract(from text: String) -> [String] {
        let pattern = #"(?<![A-Za-z0-9])(?:[0-9][ -]?){12}[0-9](?![A-Za-z0-9])|(?<![A-Za-z0-9])(?:[0-9][ -]?){9}[0-9Xx](?![A-Za-z0-9])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text), let isbn = normalize(String(text[swiftRange])), seen.insert(isbn).inserted else { return nil }
            return isbn
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { unicodeScalars.count == 1 && unicodeScalars.first!.value >= 48 && unicodeScalars.first!.value <= 57 }
}

public enum CatalogError: LocalizedError, Equatable, Sendable {
    case invalidISBN
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidISBN: "Некоректний номер ISBN. Перевірте цифри та контрольну суму."
        case .invalidResponse: "Не вдалося прочитати відповідь каталогу книг."
        case .httpStatus(429): "Каталог книг тимчасово обмежив кількість запитів. Спробуйте пізніше."
        case .httpStatus(let status): "Каталог книг повернув помилку HTTP \(status)."
        }
    }
}

public struct CatalogClient: Sendable {
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init() {
        self.fetch = { try await CatalogTransport.shared.data(for: $0) }
    }

    public init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.fetch = fetch
    }

    /// Prefers metadata in the requested language without changing any record's actual language.
    /// Ukrainian is the default when catalogues disagree about the language of an ISBN.
    public func lookup(isbn rawISBN: String, preferredLanguage: String = "uk") async throws -> [CatalogBook] {
        guard let isbn = ISBN.normalize(rawISBN) else { throw CatalogError.invalidISBN }
        var openLibraryBooks: [CatalogBook] = []
        var openLibraryError: Error?
        do {
            openLibraryBooks = try await lookupOpenLibrary(isbn: isbn)
            if openLibraryBooks.contains(where: { $0.language == preferredLanguage }) { return openLibraryBooks }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            openLibraryError = error
        }
        do {
            let books = try await MBooksCatalog(fetch: fetch).lookup(isbn: isbn, preferredLanguage: preferredLanguage)
            let combined = prioritizingLanguage(preferredLanguage, in: openLibraryBooks + books)
            if combined.isEmpty, let openLibraryError { throw openLibraryError }
            return combined
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A secondary provider is optional when the primary already returned a valid edition.
            if !openLibraryBooks.isEmpty { return openLibraryBooks }
            throw error
        }
    }

    private func lookupOpenLibrary(isbn: String) async throws -> [CatalogBook] {
        let url = try makeURL(path: "/isbn/\(isbn).json")
        guard let data = try await load(url, allowsNotFound: true) else { return [] }
        let edition: Edition
        do { edition = try JSONDecoder().decode(Edition.self, from: data) }
        catch { throw CatalogError.invalidResponse }
        guard let title = edition.title?.nonempty, let id = keyID(edition.key) else { throw CatalogError.invalidResponse }
        var authorNames: [String] = []
        for author in edition.authors ?? [] {
            try Task.checkCancellation()
            if let name = author.name?.nonempty { authorNames.append(name); continue }
            guard let key = author.key, isSafeKey(key, prefix: "/authors/") else { continue }
            let authorURL = try makeURL(path: key + ".json")
            if let authorData = try? await load(authorURL, allowsNotFound: true),
               let record = try? JSONDecoder().decode(AuthorRecord.self, from: authorData),
               let name = record.name?.nonempty { authorNames.append(name) }
            try Task.checkCancellation()
        }
        let coverID = edition.covers?.first(where: { $0 > 0 })
        let metadata = try? JSONDecoder().decode(OpenLibraryGenreMetadata.self, from: data)
        var genres = metadata?.labels ?? []
        if genres.isEmpty, let workKey = metadata?.workKey {
            do {
                let workURL = try makeURL(path: workKey + ".json")
                if let workData = try await load(workURL, allowsNotFound: true, timeout: 5) {
                    genres = (try? JSONDecoder().decode(OpenLibraryGenreMetadata.self, from: workData))?.labels ?? []
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Optional classification must never discard an otherwise valid ISBN edition.
            }
        }
        try Task.checkCancellation()
        return [CatalogBook(
            id: "openlibrary:\(id)", title: title,
            author: authorNames.joined(separator: ", "), isbn: isbn,
            language: languageCode(edition.languages?.compactMap(\.key) ?? []),
            publisher: edition.publishers?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            year: year(from: edition.publishDate), coverURL: coverURL(coverID),
            sourceName: "Open Library", sourceURL: "https://openlibrary.org/books/\(id)", genres: genres
        )]
    }

    public func search(_ query: String, language: String? = nil) async throws -> [CatalogBook] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var q = query
        if let language, let openLibraryCode = openLibraryLanguage(language) { q += " language:\(openLibraryCode)" }
        let url = try makeURL(path: "/search.json", query: [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "key,title,author_name,subject,editions,editions.key,editions.title,editions.isbn,editions.language,editions.publisher,editions.publish_date,editions.cover_i"),
            URLQueryItem(name: "limit", value: "10")
        ])
        guard let data = try await load(url) else { throw CatalogError.invalidResponse }
        let response: SearchResponse
        do { response = try JSONDecoder().decode(SearchResponse.self, from: data) }
        catch { throw CatalogError.invalidResponse }
        return response.docs.compactMap { doc in
            guard let workID = keyID(doc.key), let workTitle = doc.title?.nonempty else { return nil }
            let edition = doc.editions?.docs.first(where: { candidate in
                guard keyID(candidate.key) != nil else { return false }
                guard let language, let requested = openLibraryLanguage(language) else { return true }
                return languageCode(candidate.language ?? []) == languageCode([requested])
            })
            let editionID = edition.flatMap { keyID($0.key) }
            let preferredISBN = edition?.isbn?.compactMap(ISBN.normalize).first ?? ""
            return CatalogBook(
                id: "openlibrary:\(editionID ?? workID)",
                title: edition?.title?.nonempty ?? workTitle,
                author: doc.authorName?.joined(separator: ", ") ?? "",
                isbn: preferredISBN,
                language: languageCode(edition?.language ?? []),
                publisher: edition?.publisher?.first ?? "",
                year: year(from: edition?.publishDate),
                coverURL: coverURL(edition?.coverI),
                genres: doc.genres
            )
        }
    }

    private func load(_ url: URL, allowsNotFound: Bool = false, timeout: TimeInterval = 15) async throws -> Data? {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Bookreign/1.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await fetch(request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        if response.statusCode == 404 && allowsNotFound { return nil }
        guard (200...299).contains(response.statusCode) else { throw CatalogError.httpStatus(response.statusCode) }
        return data
    }
}

/// Stable partition keeps source order for equally preferred records.
func prioritizingLanguage(_ language: String, in books: [CatalogBook]) -> [CatalogBook] {
    books.filter { $0.language == language } + books.filter { $0.language != language }
}

private func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
    var parts = URLComponents()
    parts.scheme = "https"
    parts.host = "openlibrary.org"
    parts.path = path
    parts.queryItems = query.isEmpty ? nil : query
    guard let url = parts.url else { throw CatalogError.invalidResponse }
    return url
}

private func keyID(_ key: String?) -> String? {
    guard let key, let value = key.split(separator: "/").last.map(String.init),
          value.range(of: #"^OL[0-9]+[MW]$"#, options: .regularExpression) != nil else { return nil }
    return value
}

private func isSafeKey(_ key: String, prefix: String) -> Bool {
    key.hasPrefix(prefix) && key.dropFirst(prefix.count).range(of: #"^OL[0-9]+A$"#, options: .regularExpression) != nil
}

private func openLibraryLanguage(_ code: String) -> String? {
    switch code.lowercased() {
    case "uk", "ukr": "ukr"
    case "ru", "rus": "rus"
    case "en", "eng": "eng"
    default: nil
    }
}

private func languageCode(_ raw: [String]) -> String {
    for value in raw {
        let code = value.split(separator: "/").last.map(String.init) ?? value
        switch code.lowercased() {
        case "uk", "ukr": return "uk"
        case "ru", "rus": return "ru"
        case "en", "eng": return "en"
        default: continue
        }
    }
    return "other"
}

private func year(from date: String?) -> String {
    guard let date, let range = date.range(of: #"(?<![0-9])(?:1[5-9][0-9]{2}|20[0-9]{2}|21[0-9]{2})(?![0-9])"#, options: .regularExpression) else { return "" }
    return String(date[range])
}

private func coverURL(_ id: Int?) -> String {
    guard let id, id > 0 else { return "" }
    return "https://covers.openlibrary.org/b/id/\(id)-M.jpg"
}

private extension String {
    var nonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct Edition: Decodable {
    let key: String?
    let title: String?
    let publishers: [String]?
    let publishDate: String?
    let languages: [KeyRecord]?
    let covers: [Int]?
    let authors: [AuthorRecord]?

    enum CodingKeys: String, CodingKey {
        case key, title, publishers, languages, covers, authors
        case publishDate = "publish_date"
    }
}

private struct KeyRecord: Decodable { let key: String? }
private struct AuthorRecord: Decodable { let key: String?; let name: String? }
private struct SearchResponse: Decodable { let docs: [SearchDoc] }
private struct SearchDoc: Decodable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let editions: SearchEditions?
    let genres: [String]
    enum CodingKeys: String, CodingKey {
        case key, title, editions
        case authorName = "author_name"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        authorName = try values.decodeIfPresent([String].self, forKey: .authorName)
        editions = try values.decodeIfPresent(SearchEditions.self, forKey: .editions)
        genres = (try? OpenLibraryGenreMetadata(from: decoder))?.labels ?? []
    }
}
private struct SearchEditions: Decodable { let docs: [SearchEdition] }
private struct SearchEdition: Decodable {
    let key: String?
    let title: String?
    let isbn: [String]?
    let language: [String]?
    let publisher: [String]?
    let publishDate: String?
    let coverI: Int?
    enum CodingKeys: String, CodingKey {
        case key, title, isbn, language, publisher
        case publishDate = "publish_date"
        case coverI = "cover_i"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        isbn = try values.decodeIfPresent([String].self, forKey: .isbn)
        language = try values.decodeIfPresent([String].self, forKey: .language)
        publisher = try values.decodeIfPresent([String].self, forKey: .publisher)
        coverI = try values.decodeIfPresent(Int.self, forKey: .coverI)
        publishDate = (try? values.decode(String.self, forKey: .publishDate))
            ?? (try? values.decode([String].self, forKey: .publishDate))?.first
    }
}
