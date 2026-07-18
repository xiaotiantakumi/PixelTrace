import XCTest
@testable import PixelTraceCore

private struct SampleEncodable: Encodable {
    let name: String
    let count: Int
}

final class PixelTraceMetadataTests: XCTestCase {
    private let encoder = PixelTraceJSONCoding.makeEncoder()
    private let decoder = PixelTraceJSONCoding.makeDecoder()

    func testDictionaryLiteral() {
        let metadata: PixelTraceMetadata = ["name": "alpha", "count": 3]
        XCTAssertEqual(metadata.values["name"], .string("alpha"))
        XCTAssertEqual(metadata.values["count"], .int(3))
    }

    func testInitEncodingEncodableStruct() throws {
        let metadata = try PixelTraceMetadata(encoding: SampleEncodable(name: "alpha", count: 3))
        XCTAssertEqual(metadata.values["name"], .string("alpha"))
        XCTAssertEqual(metadata.values["count"], .int(3))
    }

    func testInitEncodingTopLevelArrayThrows() {
        XCTAssertThrowsError(try PixelTraceMetadata(encoding: [1, 2, 3])) { error in
            XCTAssertEqual(error as? PixelTraceMetadataError, .notAnObject)
        }
    }

    func testInitEncodingTopLevelIntThrows() {
        XCTAssertThrowsError(try PixelTraceMetadata(encoding: 42)) { error in
            XCTAssertEqual(error as? PixelTraceMetadataError, .notAnObject)
        }
    }

    func testEmptyEncodesToBareObject() throws {
        let data = try encoder.encode(PixelTraceMetadata.empty)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
    }

    func testRoundTrip() throws {
        let metadata: PixelTraceMetadata = ["preset": "hd4k", "width": 3840]
        let data = try encoder.encode(metadata)
        let decoded = try decoder.decode(PixelTraceMetadata.self, from: data)
        XCTAssertEqual(decoded, metadata)
    }
}
