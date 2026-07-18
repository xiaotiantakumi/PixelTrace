import XCTest
@testable import PixelTraceCore

final class PixelTraceFrameNamingTests: XCTestCase {
    func testZero() {
        XCTAssertEqual(PixelTraceFrameNaming.basename(sequence: 0), "frame_000000")
    }

    func testFortyTwo() {
        XCTAssertEqual(PixelTraceFrameNaming.basename(sequence: 42), "frame_000042")
    }

    func testLargeSequence() {
        XCTAssertEqual(PixelTraceFrameNaming.basename(sequence: 123456), "frame_123456")
    }
}
