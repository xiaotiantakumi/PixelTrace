import CoreGraphics
import CoreVideo
import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

private struct StubPNGFrameEncoder: PixelTraceFrameEncoding {
    let payload: Data

    var fileExtension: String { "png" }

    func encode(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data? {
        payload
    }
}

final class PixelTraceFrameEncodingTests: XCTestCase {
    func testCustomFrameEncoderWritesExpectedExtensionAndBytes() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let stubBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.frameEncoder = StubPNGFrameEncoder(payload: stubBytes)

        let directory = try PixelTraceSessionWriter.sessionDirectory(sessionId: "enc-1", configuration: config)
        let writer = PixelTraceSessionWriter(
            sessionId: "enc-1",
            startedAt: Date(),
            uptimeNanos: 1,
            directory: directory,
            configuration: config,
            metadata: .empty
        )
        await writer.begin()

        let frame = PixelTraceFrame(
            pixelBuffer: makeTestPixelBuffer(),
            orientation: .up,
            capturedAt: Date()
        )
        await writer.writeFrame(frame, sequence: 0)

        let frameURL = directory.appendingPathComponent("frame_000000.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: frameURL.path))
        XCTAssertEqual(try Data(contentsOf: frameURL), stubBytes)
    }
}
