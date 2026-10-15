import Foundation
import Compression
import CryptoKit

public enum FamilyAssetCodec {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let headerSize = 44

    public static func encode(_ envelope: FamilyEnvelope) throws -> Data {
        _ = try envelope.snapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let raw = try encoder.encode(envelope)
        guard raw.count <= maximumBytes else { throw FamilyError.tooLarge }
        var compressed = Data(count: raw.count + raw.count / 100 + 1024)
        let capacity = compressed.count
        let count = compressed.withUnsafeMutableBytes { output in
            raw.withUnsafeBytes { input in
                compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          input.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0, count <= maximumBytes else { throw FamilyError.tooLarge }
        compressed.count = count
        var result = Data([66, 82, 70, 49]) // BRF1
        var length = UInt64(raw.count).littleEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(contentsOf: SHA256.hash(data: raw))
        result.append(compressed)
        return result
    }

    public static func decode(_ data: Data, maximumBytes limit: Int = maximumBytes) throws -> FamilyEnvelope {
        guard limit > 0, data.count > headerSize, data.count <= min(limit, maximumBytes) + headerSize,
              data.prefix(4) == Data([66, 82, 70, 49]) else { throw FamilyError.invalidData }
        let bytes = [UInt8](data.prefix(headerSize))
        let length = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[4 + $1]) << ($1 * 8) }
        guard length > 0, length <= UInt64(min(limit, maximumBytes)) else { throw FamilyError.tooLarge }
        var raw = Data(count: Int(length) + 1)
        let capacity = raw.count
        let count = raw.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                compression_decode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          input.bindMemory(to: UInt8.self).baseAddress!.advanced(by: headerSize), data.count - headerSize, nil, COMPRESSION_ZLIB)
            }
        }
        guard count == Int(length) else { throw FamilyError.invalidData }
        raw.count = count
        guard Data(SHA256.hash(data: raw)) == data.subdata(in: 12..<headerSize) else { throw FamilyError.invalidData }
        let result = try JSONDecoder().decode(FamilyEnvelope.self, from: raw)
        _ = try result.snapshot()
        return result
    }

    /// Incremental reading also handles providers with unknown or inaccurate file sizes.
    public static func read(_ url: URL, maximumBytes: Int = maximumBytes + headerSize) throws -> Data {
        guard maximumBytes > 0, maximumBytes < Int.max else { throw FamilyError.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var result = Data()
        while let chunk = try file.read(upToCount: min(65_536, maximumBytes - result.count + 1)), !chunk.isEmpty {
            guard result.count <= maximumBytes - chunk.count else { throw FamilyError.tooLarge }
            result.append(chunk)
        }
        return result
    }
}
