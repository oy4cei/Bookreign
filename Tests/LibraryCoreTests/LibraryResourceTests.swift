import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import LibraryCore

final class LibraryResourceTests: XCTestCase {
    func testBoundedReadRefusesOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: 4096).write(to: url)
        XCTAssertThrowsError(try FamilyAssetCodec.read(url, maximumBytes: 1024))
        XCTAssertEqual(try FamilyAssetCodec.read(url, maximumBytes: 4096).count, 4096)
    }
    func testImportedOversizedTextCannotReplaceDatabase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try LibraryDatabase(url: url)
        let original = try database.load()
        var hostile = original
        hostile.editions = [BookEdition(title: String(repeating: "x", count: 1_048_577))]
        let data = try LibraryBackup.encode(hostile)
        XCTAssertThrowsError(try LibraryBackup.decode(data))
        XCTAssertEqual(try database.load(), original)
    }
    func testStoredImageThumbnailUsesSmallOutputEvenForLargeOriginal() throws {
        let color = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 2048, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: color, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let thumbnail = try XCTUnwrap(LibraryImageSafety.thumbnail(data as Data, maximumDimension: 128))
        XCTAssertLessThanOrEqual(thumbnail.width, 128)
        XCTAssertLessThanOrEqual(thumbnail.height, 128)
    }
}
