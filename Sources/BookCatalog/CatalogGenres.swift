import Foundation

/// Catalog labels stay in their source language. Broad subject lists also contain people,
/// places and plot details; only explicit, recognized genre labels from those lists qualify.
struct OpenLibraryGenreMetadata: Decodable {
    let labels: [String]
    let workKey: String?

    private enum CodingKeys: String, CodingKey { case genres, subjects, subject, works }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let genres = (try? values.decode([OptionalGenreString].self, forKey: .genres))?.compactMap(\.value) ?? []
        let subjects = (try? values.decode([OptionalGenreString].self, forKey: .subjects))?.compactMap(\.value)
            ?? (try? values.decode([OptionalGenreString].self, forKey: .subject))?.compactMap(\.value) ?? []
        labels = uniqueGenreLabels(genres + subjects.filter { recognizedSubjectGenres.contains(genreComparisonKey($0)) })
        let works = (try? values.decode([OptionalWorkKey].self, forKey: .works)) ?? []
        workKey = works.compactMap(\.key).first { key in
            key.range(of: #"^/works/OL[0-9]+W$"#, options: .regularExpression) != nil
        }
    }
}

struct MBooksGenreMetadata: Decodable {
    let labels: [String]
    private enum CodingKeys: String, CodingKey {
        case mainCategory = "main_category", additionalCategories = "additional_categories"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let main = try? values.decode(OptionalCategory.self, forKey: .mainCategory)
        let additional = (try? values.decode([OptionalCategory].self, forKey: .additionalCategories)) ?? []
        labels = ([main?.title] + additional.map(\.title)).compactMap { $0 }
    }
}

func uniqueGenreLabels(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { raw in
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Open Library also returns internal genre tag references instead of readable labels.
        guard !value.isEmpty, value.count <= 120, !value.hasPrefix("/"),
              !value.contains("://"), seen.insert(genreComparisonKey(value)).inserted else { return nil }
        return value
    }
}

private func genreComparisonKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        .lowercased()
}

private let recognizedSubjectGenres: Set<String> = [
    "fiction", "nonfiction", "non-fiction", "novels", "romance", "romance fiction", "historical fiction",
    "science fiction", "fantasy", "fantasy fiction", "detective and mystery stories", "mystery fiction",
    "thrillers", "thrillers (fiction)", "horror tales", "horror fiction", "humorous stories",
    "adventure stories", "short stories", "poetry", "drama", "plays", "essays", "biography",
    "autobiography", "memoirs", "fairy tales", "fables", "comics", "graphic novels", "juvenile fiction",
    "juvenile literature", "children's fiction", "children's stories", "children's literature",
    "children's poetry", "children's plays",
    "художня література", "художественная литература", "романи", "романы", "роман", "фантастика",
    "наукова фантастика", "научная фантастика", "фентезі", "фэнтези", "детективи", "детективы",
    "поезія", "поэзия", "вірші", "стихи", "оповідання", "рассказы", "казки", "сказки",
    "біографія", "биография", "біографії", "биографии", "мемуари", "мемуары", "есе", "эссе",
    "дитяча література", "детская литература", "комікси", "комиксы"
]

private struct OptionalGenreString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}

private struct OptionalWorkKey: Decodable {
    let key: String?
    private enum CodingKeys: String, CodingKey { case key }
    init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        key = try? values?.decode(String.self, forKey: .key)
    }
}

private struct OptionalCategory: Decodable {
    let title: String?
    private enum CodingKeys: String, CodingKey { case title }
    init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        title = try? values?.decode(String.self, forKey: .title)
    }
}
