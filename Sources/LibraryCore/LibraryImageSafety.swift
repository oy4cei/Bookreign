import Foundation
import ImageIO

/// Inspect dimensions before decoding pixels; never render a full-resolution imported image.
public enum LibraryImageSafety {
    public static let maximumBytes = 12 * 1_024 * 1_024
    public static let maximumPixels = 100_000_000

    public static func accepts(_ data: Data) -> Bool {
        guard data.count <= maximumBytes else { return false }
        // Older backups may contain a broken cover. It can be retained safely as a placeholder.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return true }
        return dimensionsAreSafe(source) != false
    }

    public static func thumbnail(_ data: Data, maximumDimension: Int = 1_600) -> CGImage? {
        guard data.count <= maximumBytes, maximumDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              dimensionsAreSafe(source) == true else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumDimension, 1_600),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func dimensionsAreSafe(_ source: CGImageSource) -> Bool? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value else { return nil }
        guard width > 0, height > 0, width <= maximumPixels, height <= maximumPixels else { return false }
        return width <= Int64(maximumPixels) / height
    }
}

public enum LibraryResourceLimits {
    public static let maximumBackupBytes = 64 * 1_024 * 1_024
    public static let maximumFieldBytes = 1_024 * 1_024

    public static func validate(_ snapshot: LibrarySnapshot) throws {
        guard snapshot.editions.count + snapshot.copies.count + snapshot.locations.count + snapshot.loans.count <= 100_000 else { throw FamilyError.tooLarge }
        var total = 0
        func text(_ values: [String]) throws {
            for value in values {
                let bytes = value.utf8.count
                guard bytes <= maximumFieldBytes, bytes <= maximumBackupBytes - total else { throw FamilyError.tooLarge }
                total += bytes
            }
        }
        for book in snapshot.editions {
            try text([book.title, book.author, book.isbn, book.language, book.publisher, book.year, book.coverURL, book.notes] + book.genres)
            if let cover = book.coverData {
                guard LibraryImageSafety.accepts(cover), cover.count <= maximumBackupBytes - total else { throw FamilyError.tooLarge }
                total += cover.count
            }
        }
        for copy in snapshot.copies { try text([copy.shelf]) }
        for place in snapshot.locations { try text([place.name, place.symbol]) }
        for loan in snapshot.loans { try text([loan.borrower]) }
    }
}
