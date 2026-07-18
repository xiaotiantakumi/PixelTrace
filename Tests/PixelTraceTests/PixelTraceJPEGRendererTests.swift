import CoreImage
import ImageIO
import XCTest
@testable import PixelTrace

final class PixelTraceJPEGRendererTests: XCTestCase {
    private let softwareContext = CIContext(options: [.useSoftwareRenderer: true])

    func testProducesValidJPEG() {
        let data = PixelTraceJPEGRenderer.renderJPEG(
            pixelBuffer: makeTestPixelBuffer(width: 128, height: 96),
            orientation: .up,
            context: softwareContext
        )
        let bytes = try? XCTUnwrap(data)
        XCTAssertNotNil(bytes)
        XCTAssertTrue(bytes?.prefix(2).elementsEqual([0xFF, 0xD8]) ?? false, "JPEG SOI marker missing")
    }

    func testDownscaleAboveMaxLongEdgeStillRenders() {
        let data = PixelTraceJPEGRenderer.renderJPEG(
            pixelBuffer: makeTestPixelBuffer(width: 400, height: 200),
            orientation: .up,
            maxLongEdge: 100,
            context: softwareContext
        )
        XCTAssertNotNil(data)
    }

    func testOrientedRenderRenders() {
        let data = PixelTraceJPEGRenderer.renderJPEG(
            pixelBuffer: makeTestPixelBuffer(width: 120, height: 80),
            orientation: .right,
            context: softwareContext
        )
        XCTAssertNotNil(data)
    }
}
