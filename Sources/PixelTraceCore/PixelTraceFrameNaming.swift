import Foundation

public enum PixelTraceFrameNaming {
    public static func basename(sequence: Int) -> String {
        "frame_" + String(format: "%06d", sequence)
    }
}
