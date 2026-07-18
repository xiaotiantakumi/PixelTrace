import Foundation

public enum PixelTraceMetadataError: Error {
    case notAnObject
}

public struct PixelTraceMetadata: Sendable, Equatable, Codable {
    public var values: [String: PixelTraceJSONValue]

    public static let empty = PixelTraceMetadata([:])

    public init(_ values: [String: PixelTraceJSONValue]) {
        self.values = values
    }

    public init<E: Encodable>(encoding value: E) throws {
        let encoder = PixelTraceJSONCoding.makeEncoder()
        let data = try encoder.encode(value)
        let decoded = try PixelTraceJSONCoding.makeDecoder().decode(PixelTraceJSONValue.self, from: data)
        guard case .object(let object) = decoded else {
            throw PixelTraceMetadataError.notAnObject
        }
        self.values = object
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: PixelTraceJSONValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

extension PixelTraceMetadata: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, PixelTraceJSONValue)...) {
        values = Dictionary(uniqueKeysWithValues: elements)
    }
}
