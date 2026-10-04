import Foundation

/// Public MEGOGO BOOKS endpoints used by its own search and product pages.
/// A search hit is never treated as an ISBN match until its product record confirms the ISBN.
struct MBooksCatalog {
    let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func lookup(isbn: String, preferredLanguage: String = "uk") async throws -> [CatalogBook] {
        let canonicalISBN = ISBN.canonical(isbn) ?? isbn
        let searchURL = try apiURL(path: "/api/v1/search/main/", query: [
            URLQueryItem(name: "query", value: canonicalISBN),
            URLQueryItem(name: "groups", value: "books,authors,publishers,series,certificates"),
            URLQueryItem(name: "limit", value: "24")
        ])
        let search: SearchEnvelope
        do { search = try JSONDecoder().decode(SearchEnvelope.self, from: try await load(searchURL)) }
        catch is CancellationError { throw CancellationError() }
        catch let error as CatalogError { throw error }
        catch { throw CatalogError.invalidResponse }
        guard search.status == "success", search.code == 200 else { throw CatalogError.invalidResponse }

        let candidates = search.data.items.books.items
        var matches: [CatalogBook] = []
        var candidateError: Error?
        for candidate in candidates.prefix(3) {
            try Task.checkCancellation()
            do {
                guard isSafeSlug(candidate.slug) else { throw CatalogError.invalidResponse }
                let detailURL = try apiURL(path: "/api/v1/books/\(candidate.slug)/")
                let detail: DetailEnvelope
                do { detail = try JSONDecoder().decode(DetailEnvelope.self, from: try await load(detailURL)) }
                catch is CancellationError { throw CancellationError() }
                catch let error as CatalogError { throw error }
                catch { throw CatalogError.invalidResponse }
                guard detail.status == "success", detail.code == 200 else { throw CatalogError.invalidResponse }
                let book = detail.data.item
                guard book.slug == candidate.slug else { throw CatalogError.invalidResponse }
                guard ISBN.canonical(book.isbn) == canonicalISBN else { continue }
                guard let title = book.title.trimmedNonempty else { throw CatalogError.invalidResponse }
                let authors = book.authors.map { author in
                    [author.firstName, author.lastName].compactMap { $0?.trimmedNonempty }.joined(separator: " ")
                }.filter { !$0.isEmpty }
                let webURL = "https://mbooks.com.ua/book/\(candidate.slug)/"
                matches.append(CatalogBook(
                    id: "mbooks:\(candidate.slug)",
                    title: decodeHTMLEntities(title),
                    author: decodeHTMLEntities(authors.joined(separator: ", ")),
                    isbn: canonicalISBN,
                    language: catalogLanguage(book.languages),
                    publisher: decodeHTMLEntities(book.publisher?.name ?? ""),
                    year: book.year.map(String.init) ?? "",
                    coverURL: secureURL(book.cover?.frontCover),
                    sourceName: "MEGOGO BOOKS",
                    sourceURL: webURL,
                    genres: uniqueGenreLabels(book.genres.map(decodeHTMLEntities))
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                candidateError = candidateError ?? error
            }
        }
        if !matches.isEmpty { return prioritizingLanguage(preferredLanguage, in: matches) }
        if let candidateError { throw candidateError }
        // The search endpoint may return more candidates than this bounded lookup checks.
        // In that case absence of a verified ISBN cannot be claimed.
        if candidates.count > 3 || search.data.items.books.total > candidates.count {
            throw CatalogError.invalidResponse
        }
        return []
    }

    private func load(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bookreign/1.0.0 (book catalog)", forHTTPHeaderField: "User-Agent")
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
        guard (200...299).contains(response.statusCode) else { throw CatalogError.httpStatus(response.statusCode) }
        return data
    }

    private func apiURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.mbooks.com.ua"
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw CatalogError.invalidResponse }
        return url
    }
}

private func isSafeSlug(_ slug: String) -> Bool {
    !slug.isEmpty && slug.count <= 200
        && slug.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
}

private func secureURL(_ raw: String?) -> String {
    guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return "" }
    return raw
}

private func catalogLanguage(_ values: [String]) -> String {
    for value in values {
        switch value.lowercased() {
        case "українська", "украинский", "uk", "ukr": return "uk"
        case "російська", "русский", "ru", "rus": return "ru"
        case "англійська", "английский", "english", "en", "eng": return "en"
        default: continue
        }
    }
    return "other"
}

private func decodeHTMLEntities(_ text: String) -> String {
    let pattern = #"&(#(?:[0-9]+|[xX][0-9A-Fa-f]+)|[A-Za-z]+);"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    var output = text
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    for match in matches.reversed() {
        guard let range = Range(match.range, in: output),
              let codeRange = Range(match.range(at: 1), in: text) else { continue }
        let code = String(text[codeRange])
        let replacement: String?
        if code.hasPrefix("#") {
            let number = String(code.dropFirst())
            let scalar: UInt32?
            if number.lowercased().hasPrefix("x") {
                scalar = UInt32(number.dropFirst(), radix: 16)
            } else {
                scalar = UInt32(number)
            }
            replacement = scalar.flatMap(Unicode.Scalar.init).map(String.init)
        } else {
            replacement = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">",
                           "nbsp": " ", "mdash": "—", "ndash": "–", "laquo": "«", "raquo": "»"][code]
        }
        if let replacement { output.replaceSubrange(range, with: replacement) }
    }
    return output
}

private extension String {
    var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct SearchEnvelope: Decodable {
    let status: String
    let code: Int
    let data: SearchData
}
private struct SearchData: Decodable { let items: SearchGroups }
private struct SearchGroups: Decodable { let books: SearchBooks }
private struct SearchBooks: Decodable {
    let items: [SearchItem]
    let total: Int
}
private struct SearchItem: Decodable { let slug: String }

private struct DetailEnvelope: Decodable {
    let status: String
    let code: Int
    let data: DetailData
}
private struct DetailData: Decodable { let item: DetailBook }
private struct DetailBook: Decodable {
    let slug: String
    let title: String
    let isbn: String
    let year: Int?
    let languages: [String]
    let publisher: DetailPublisher?
    let authors: [DetailAuthor]
    let cover: DetailCover?
    let genres: [String]

    private enum CodingKeys: String, CodingKey {
        case slug, title, isbn, year, languages, publisher, authors, cover
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        slug = try values.decode(String.self, forKey: .slug)
        title = try values.decode(String.self, forKey: .title)
        isbn = try values.decode(String.self, forKey: .isbn)
        year = try values.decodeIfPresent(Int.self, forKey: .year)
        languages = try values.decode([String].self, forKey: .languages)
        publisher = try values.decodeIfPresent(DetailPublisher.self, forKey: .publisher)
        authors = try values.decode([DetailAuthor].self, forKey: .authors)
        cover = try values.decodeIfPresent(DetailCover.self, forKey: .cover)
        genres = (try? MBooksGenreMetadata(from: decoder))?.labels ?? []
    }
}
private struct DetailPublisher: Decodable { let name: String }
private struct DetailAuthor: Decodable {
    let firstName: String?
    let lastName: String?
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name", lastName = "last_name"
    }
}
private struct DetailCover: Decodable {
    let frontCover: String?
    enum CodingKeys: String, CodingKey { case frontCover = "front_cover" }
}
