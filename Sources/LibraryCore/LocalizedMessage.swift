import Foundation

/// A deferred UI message. Interpolated values are data, never translation keys.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable, Equatable {
    public let key: String
    public let arguments: [String]

    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }
    private init(key: String, arguments: [String]) { self.key = key; self.arguments = arguments }
    public static func verbatim(_ value: String) -> Self { .init(key: "{0}", arguments: [value]) }
    public func rendered(template: String? = nil) -> String {
        let source = template ?? key
        var output = ""
        var position = source.startIndex
        while position < source.endIndex {
            if source[position] == "{", let end = source[position...].firstIndex(of: "}"),
               let index = Int(source[source.index(after: position)..<end]), arguments.indices.contains(index) {
                output += arguments[index]
                position = source.index(after: end)
            } else {
                output.append(source[position])
                position = source.index(after: position)
            }
        }
        return output
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ value: String) { key += value }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}
