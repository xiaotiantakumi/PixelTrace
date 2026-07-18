import XCTest
@testable import PixelTraceCore

final class FourCCFormattingTests: XCTestCase {
    func testKnownFourCC() {
        XCTAssertEqual(FourCCFormatting.string(from: 875704422), "420f")
    }

    func testNonPrintableReturnsHexPrefix() {
        let result = FourCCFormatting.string(from: 0x00000001)
        XCTAssertTrue(result.hasPrefix("0x"))
    }
}
