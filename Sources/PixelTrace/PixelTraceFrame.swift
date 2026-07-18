import CoreVideo
import Foundation
import ImageIO
import PixelTraceCore

/// One frame of recording input.
///
/// `@unchecked Sendable` rationale: while this value holds a strong reference to the
/// pixel buffer, the buffer pool cannot recycle it, so the contents are preserved. The
/// buffer is consumed by a single writer and is never accessed concurrently.
public struct PixelTraceFrame: @unchecked Sendable {
    /// The pixel buffer the host pipeline is processing for this frame.
    public let pixelBuffer: CVPixelBuffer
    /// The same orientation the host passed to its analysis pipeline. The recorded JPEG is
    /// drawn in this orientation so that "what the pipeline saw" can be reviewed later.
    public let orientation: CGImagePropertyOrientation
    /// Wall-clock time the frame was captured. Prefer the presentation time of the sample
    /// buffer when available so recorded frames line up with host logs (see spec §10.4).
    public let capturedAt: Date
    /// Host-defined metadata attached to this frame's sidecar.
    public let metadata: PixelTraceMetadata

    public init(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        capturedAt: Date = Date(),
        metadata: PixelTraceMetadata = .empty
    ) {
        self.pixelBuffer = pixelBuffer
        self.orientation = orientation
        self.capturedAt = capturedAt
        self.metadata = metadata
    }
}
