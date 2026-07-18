import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// Renders a `CVPixelBuffer` to JPEG, preserving the orientation the pipeline analyzed.
///
/// The buffer is drawn at native resolution by default; the long edge is only scaled down
/// when it exceeds `maxLongEdge` (a safety valve for above-4K buffers). Scaling is avoided by
/// default so a reviewer can tell whether text is unreadable because of the capture itself
/// rather than because the recorder downscaled it (spec §5.5). Storage is bounded by the
/// session limits, not by downscaling.
public enum PixelTraceJPEGRenderer {
    public static func renderJPEG(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        maxLongEdge: CGFloat = 3840,
        quality: CGFloat = 0.8,
        context: CIContext? = nil
    ) -> Data? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        // `CIImage.oriented(_:)` applies the same transform that vision/analysis frameworks
        // apply for a given CGImagePropertyOrientation, so the output is "what the pipeline saw".
        let oriented = source.oriented(orientation)
        let normalized = oriented.transformed(
            by: CGAffineTransform(translationX: -oriented.extent.origin.x, y: -oriented.extent.origin.y)
        )

        let output = scaledForExport(normalized, maxLongEdge: maxLongEdge)

        let renderContext = context ?? CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return renderContext.jpegRepresentation(
            of: output,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }

    /// Scales the image down only when its long edge exceeds the limit.
    private static func scaledForExport(_ image: CIImage, maxLongEdge: CGFloat) -> CIImage {
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)
        guard maxLongEdge > 0, longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaled.transformed(
            by: CGAffineTransform(translationX: -scaled.extent.origin.x, y: -scaled.extent.origin.y)
        )
    }
}
