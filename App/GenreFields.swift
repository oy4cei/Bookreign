import SwiftUI
import LibraryCore

struct GenreFields: View {
    @Binding private var genres: [String]
    @State private var text: String

    init(genres: Binding<[String]>) {
        _genres = genres
        _text = State(initialValue: genres.wrappedValue.joined(separator: "; "))
    }

    var body: some View {
        Section {
            TextField(L("Например: роман; фантастика"), text: Binding(
                get: { text },
                set: { value in
                    text = value
                    genres = parsed(value)
                }
            ), axis: .vertical)
            .lineLimit(1...4)
            .accessibilityLabel(L("Жанры"))
            .accessibilityIdentifier("bookGenres")
        } header: {
            Text(L("Жанры"))
        } footer: {
            Text(L("Жанры из каталога можно исправить или указать вручную. Разделяйте их точкой с запятой."))
        }
        .archiveRow()
        .onChange(of: genres) { _, value in
            // External metadata can replace the draft. Do not strip a separator or
            // space the user has just typed while updating the bound values.
            if parsed(text) != value { text = value.joined(separator: "; ") }
        }
    }

    private func parsed(_ value: String) -> [String] {
        BookEdition.normalizedGenres(value.components(separatedBy: ";"))
    }
}
