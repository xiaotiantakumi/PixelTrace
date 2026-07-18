import XCTest
@testable import PixelTraceCore

final class PixelTraceJSONValueTests: XCTestCase {
    private let encoder = PixelTraceJSONCoding.makeEncoder()
    private let decoder = PixelTraceJSONCoding.makeDecoder()

    private func roundTrip(_ value: PixelTraceJSONValue, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(PixelTraceJSONValue.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    func testStringRoundTrip() throws {
        try roundTrip(.string("hello"))
    }

    func testIntRoundTrip() throws {
        try roundTrip(.int(42))
    }

    func testDoubleRoundTrip() throws {
        try roundTrip(.double(3.14))
    }

    func testBoolRoundTrip() throws {
        try roundTrip(.bool(true))
    }

    func testNullRoundTrip() throws {
        try roundTrip(.null)
    }

    func testArrayRoundTrip() throws {
        try roundTrip(.array([.int(1), .string("two")]))
    }

    func testObjectRoundTrip() throws {
        try roundTrip(.object(["key": .string("value")]))
    }

    func testLiteralInitializers() {
        let stringValue: PixelTraceJSONValue = "hello"
        XCTAssertEqual(stringValue, .string("hello"))

        let intValue: PixelTraceJSONValue = 7
        XCTAssertEqual(intValue, .int(7))

        let doubleValue: PixelTraceJSONValue = 2.5
        XCTAssertEqual(doubleValue, .double(2.5))

        let boolValue: PixelTraceJSONValue = true
        XCTAssertEqual(boolValue, .bool(true))

        let nullValue: PixelTraceJSONValue = nil
        XCTAssertEqual(nullValue, .null)
    }

    func testBoolDecodedBeforeInt() throws {
        let data = Data("true".utf8)
        let decoded = try decoder.decode(PixelTraceJSONValue.self, from: data)
        XCTAssertEqual(decoded, .bool(true))
    }
}
