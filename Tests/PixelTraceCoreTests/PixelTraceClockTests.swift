import XCTest
@testable import PixelTraceCore

final class PixelTraceClockTests: XCTestCase {
    func testStringEndsWithZ() {
        let string = PixelTraceClock.string(from: Date())
        XCTAssertTrue(string.hasSuffix("Z"))
    }

    func testRoundTripPreservesMilliseconds() throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 7
        components.day = 18
        components.hour = 4
        components.minute = 11
        components.second = 0
        components.nanosecond = 3_000_000
        let date = calendar.date(from: components)!

        let string = PixelTraceClock.string(from: date)
        XCTAssertEqual(string, "2026-07-18T04:11:00.003Z")

        let parsed = try XCTUnwrap(PixelTraceClock.date(from: string))
        XCTAssertEqual(PixelTraceClock.string(from: parsed), string)
    }

    func testKnownDateProducesExpectedString() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 7
        components.day = 18
        components.hour = 4
        components.minute = 11
        components.second = 0
        components.nanosecond = 3_000_000
        let date = calendar.date(from: components)!

        XCTAssertEqual(PixelTraceClock.string(from: date), "2026-07-18T04:11:00.003Z")
    }

    func testNowReturnsNonZeroUptime() {
        let timestamp = PixelTraceClock.now()
        XCTAssertGreaterThan(timestamp.uptimeNanos, 0)
    }
}
