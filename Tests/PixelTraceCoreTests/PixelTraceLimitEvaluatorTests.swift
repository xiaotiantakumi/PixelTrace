import XCTest
@testable import PixelTraceCore

final class PixelTraceLimitEvaluatorTests: XCTestCase {
    func testDurationOnly() {
        let limits = PixelTraceLimits(maxDuration: 100, maxTotalBytes: 1_000_000)
        XCTAssertEqual(
            PixelTraceLimitEvaluator.stopReason(elapsed: 100, totalBytes: 0, limits: limits),
            .durationLimit
        )
    }

    func testByteOnly() {
        let limits = PixelTraceLimits(maxDuration: 100, maxTotalBytes: 500)
        XCTAssertEqual(
            PixelTraceLimitEvaluator.stopReason(elapsed: 50, totalBytes: 500, limits: limits),
            .byteLimit
        )
    }

    func testBothExceedDurationWins() {
        let limits = PixelTraceLimits(maxDuration: 100, maxTotalBytes: 500)
        XCTAssertEqual(
            PixelTraceLimitEvaluator.stopReason(elapsed: 100, totalBytes: 500, limits: limits),
            .durationLimit
        )
    }

    func testNeitherReturnsNil() {
        let limits = PixelTraceLimits(maxDuration: 100, maxTotalBytes: 500)
        XCTAssertNil(
            PixelTraceLimitEvaluator.stopReason(elapsed: 99, totalBytes: 499, limits: limits)
        )
    }

    func testCustomLimits() {
        let limits = PixelTraceLimits(maxDuration: 30, maxTotalBytes: 1024)
        XCTAssertEqual(
            PixelTraceLimitEvaluator.stopReason(elapsed: 10, totalBytes: 1024, limits: limits),
            .byteLimit
        )
        XCTAssertNil(
            PixelTraceLimitEvaluator.stopReason(elapsed: 10, totalBytes: 1023, limits: limits)
        )
    }
}
