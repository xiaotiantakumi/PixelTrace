import CoreVideo
import Foundation

/// Creates a blank pixel buffer for tests.
func makeTestPixelBuffer(
    width: Int = 64,
    height: Int = 48,
    format: OSType = kCVPixelFormatType_32BGRA
) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        format,
        attributes as CFDictionary,
        &buffer
    )
    precondition(status == kCVReturnSuccess, "failed to allocate test pixel buffer")
    return buffer!
}

/// Returns a unique temporary directory URL (not yet created on disk).
func makeTestTempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("pixeltrace-tests-\(UUID().uuidString)", isDirectory: true)
}
