import ImageIO

/// Maps `CGImagePropertyOrientation` to the stable label written to frame sidecars.
enum PixelTraceOrientationMapping {
    static func label(for orientation: CGImagePropertyOrientation) -> String {
        switch orientation {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .upMirrored: return "upMirrored"
        case .downMirrored: return "downMirrored"
        case .leftMirrored: return "leftMirrored"
        case .rightMirrored: return "rightMirrored"
        @unknown default: return "unknown"
        }
    }
}
