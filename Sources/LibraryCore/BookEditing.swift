import Foundation

extension BookEdition {
    /// Apply only the fields actually edited since the form opened.
    /// Other fields may have received newer values through family synchronization.
    public func applyingEdits(_ edited: Self, from original: Self) -> Self {
        guard id == edited.id, id == original.id else { return self }
        var result = self
        for key: WritableKeyPath<Self, String> in [\.title, \.author, \.isbn, \.language, \.publisher, \.year, \.coverURL, \.notes] {
            if edited[keyPath: key] != original[keyPath: key] { result[keyPath: key] = edited[keyPath: key] }
        }
        if edited.coverData != original.coverData { result.coverData = edited.coverData }
        if edited.genres != original.genres { result.genres = edited.genres }
        return result
    }
}
