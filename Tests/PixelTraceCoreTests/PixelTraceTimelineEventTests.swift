import XCTest
@testable import PixelTraceCore

final class PixelTraceTimelineEventTests: XCTestCase {
    private let encoder = PixelTraceJSONCoding.makeEncoder()
    private let decoder = PixelTraceJSONCoding.makeDecoder()

    private func isoDate(ms: Int = 880) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 7
        components.day = 18
        components.hour = 4
        components.minute = 11
        components.second = 0
        components.nanosecond = ms * 1_000_000
        let raw = calendar.date(from: components)!
        // Normalize to the canonical millisecond serialization precision (§10.2) so that
        // encode→decode round-trip equality is exact (sub-ms precision is dropped by design).
        return PixelTraceClock.date(from: PixelTraceClock.string(from: raw))!
    }

    private func assertSingleLineJSON(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("\n"), file: file, line: line)
        XCTAssertTrue(json.contains("\"type\""), file: file, line: line)
        XCTAssertTrue(json.contains("\"timestamp\""), file: file, line: line)
        XCTAssertTrue(json.contains("\"payload\""), file: file, line: line)
    }

    func testTapEncodeDecodeRoundTrip() throws {
        let event = PixelTraceTimelineEvent.tap(
            timestamp: isoDate(),
            payload: PixelTraceTapPayload(
                x: 196.5,
                y: 642.0,
                windowWidth: 393,
                windowHeight: 852,
                screen: "main",
                phase: "down"
            )
        )

        let data = try encoder.encode(event)
        assertSingleLineJSON(data)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"type\":\"tap\""))

        let decoded = try decoder.decode(PixelTraceTimelineEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.type, .tap)
        XCTAssertEqual(decoded.timestamp, event.timestamp)
    }

    func testNetworkEncodeDecodeRoundTrip() throws {
        let event = PixelTraceTimelineEvent.network(
            timestamp: isoDate(ms: 204),
            payload: PixelTraceNetworkPayload(
                endpoint: "/v1/messages",
                method: "POST",
                statusCode: 200,
                latencyMs: 812.4,
                requestHeaders: ["authorization": "***"],
                metadata: ["model": "test"]
            )
        )

        let data = try encoder.encode(event)
        assertSingleLineJSON(data)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"type\":\"network\""))

        let decoded = try decoder.decode(PixelTraceTimelineEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testMarkerEncodeDecodeRoundTrip() throws {
        let event = PixelTraceTimelineEvent.marker(
            timestamp: isoDate(ms: 10),
            payload: PixelTraceMarkerPayload(
                name: "user_reported_issue",
                metadata: ["note": "detection missed"]
            )
        )

        let data = try encoder.encode(event)
        assertSingleLineJSON(data)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"type\":\"marker\""))

        let decoded = try decoder.decode(PixelTraceTimelineEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testEquality() {
        let timestamp = isoDate()
        let tapA = PixelTraceTimelineEvent.tap(
            timestamp: timestamp,
            payload: PixelTraceTapPayload(x: 1, y: 2, windowWidth: 100, windowHeight: 200, phase: "down")
        )
        let tapB = PixelTraceTimelineEvent.tap(
            timestamp: timestamp,
            payload: PixelTraceTapPayload(x: 1, y: 2, windowWidth: 100, windowHeight: 200, phase: "down")
        )
        XCTAssertEqual(tapA, tapB)
    }
}
