import Foundation

public enum LibraryBrowse {
    /// Missing metadata is distinct from any user-entered author or genre name.
    public enum Filter: Hashable, Sendable {
        case all
        case value(String)
        case missing
    }

    public static func editions(
        in snapshot: LibrarySnapshot, query: String = "", author: Filter = .all,
        genre: Filter = .all, ascending: Bool = true, locale: Locale
    ) -> [BookEdition] {
        snapshot.editions.filter { edition in
            snapshot.matches(edition, query: query)
                && matches([edition.author], filter: author)
                && matches(edition.genres, filter: genre)
        }.sorted { first, second in
            let order = first.title.compare(second.title, options: .caseInsensitive, locale: locale)
            if order == .orderedSame { return first.id.uuidString < second.id.uuidString }
            return order == (ascending ? .orderedAscending : .orderedDescending)
        }
    }

    public static func authors(in snapshot: LibrarySnapshot, locale: Locale) -> [String] {
        options(snapshot.editions.map(\.author), locale: locale)
    }

    public static func genres(in snapshot: LibrarySnapshot, locale: Locale) -> [String] {
        options(snapshot.editions.flatMap(\.genres), locale: locale)
    }

    private static func matches(_ values: [String], filter: Filter) -> Bool {
        switch filter {
        case .all:
            return true
        case .missing:
            return values.allSatisfy { normalized($0).isEmpty }
        case .value(let value):
            let expected = normalized(value)
            return values.contains { normalized($0) == expected }
        }
    }

    private static func normalized(_ value: String) -> String {
        LibrarySnapshot.normalizedSearchText(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func options(_ values: [String], locale: Locale) -> [String] {
        BookEdition.normalizedGenres(values).sorted { first, second in
            let order = first.compare(second, options: .caseInsensitive, locale: locale)
            // Locale collation can consider some distinct strings equivalent.
            return order == .orderedSame ? first < second : order == .orderedAscending
        }
    }
}
