import Foundation

/// Shared rules for cover discovery. Book metadata is never merged when choosing a cover.
public enum CoverSearch {
    public static let maximumImageBytes = 12 * 1024 * 1024

    public static func imageURL(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        return url
    }

    public static func candidates(from books: [CatalogBook]) -> [CatalogBook] {
        var seen = Set<String>()
        return books.compactMap { book in
            guard let url = imageURL(book.coverURL), seen.insert(url.absoluteString).inserted else { return nil }
            var candidate = book
            candidate.coverURL = url.absoluteString
            return candidate
        }
    }

    public static func webSearchURL(query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "www.google.com"
        parts.path = "/search"
        parts.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: query)]
        return parts.url
    }

    public static func validateImageResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              let url = response.url, imageURL(url.absoluteString) != nil,
              (200...299).contains(response.statusCode) else { throw CoverImageError.unavailable }
        guard let type = response.mimeType?.lowercased(), type.hasPrefix("image/") else { throw CoverImageError.notImage }
        guard response.expectedContentLength <= maximumImageBytes else { throw CoverImageError.tooLarge }
    }
}

public enum CoverImageError: Error, Equatable, Sendable {
    case invalidURL
    case unavailable
    case notImage
    case tooLarge
}
