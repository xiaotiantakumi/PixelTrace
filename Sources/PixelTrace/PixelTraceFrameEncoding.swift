import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// Encodes a captured frame to an on-disk representation.
public protocol PixelTraceFrameEncoding: Sendable {
    /// File extension without a leading dot (e.g. `"jpg"`, `"png"`).
    var fileExtension: String { get }

    func encode(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data?
}

/// Default JPEG encoder backed by `PixelTraceJPEGRenderer`.
public struct PixelTraceJPEGFrameEncoder: PixelTraceFrameEncoding {
    public var quality: CGFloat
    public var maxLongEdge: CGFloat

    public init(quality: CGFloat = 0.8, maxLongEdge: CGFloat = 3840) {
        self.quality = quality
        self.maxLongEdge = maxLongEdge
    }

    public var fileExtension: String { "jpg" }

    public func encode(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data? {
        PixelTraceJPEGRenderer.renderJPEG(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            maxLongEdge: maxLongEdge,
            quality: quality
        )
    }
}
