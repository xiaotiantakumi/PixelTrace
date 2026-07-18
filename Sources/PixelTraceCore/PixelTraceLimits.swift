import Foundation

public struct PixelTraceLimits: Sendable, Equatable {
    public var maxDuration: TimeInterval
    public var maxTotalBytes: Int

    public init(maxDuration: TimeInterval = 600, maxTotalBytes: Int = 500 * 1024 * 1024) {
        self.maxDuration = maxDuration
        self.maxTotalBytes = maxTotalBytes
    }

    public static let `default` = PixelTraceLimits()
}

public enum PixelTraceLimitEvaluator {
    public static func stopReason(
        elapsed: TimeInterval,
        totalBytes: Int,
        limits: PixelTraceLimits
    ) -> PixelTraceLimitStopReason? {
        let durationExceeded = elapsed >= limits.maxDuration
        let bytesExceeded = totalBytes >= limits.maxTotalBytes

        if durationExceeded && bytesExceeded {
            return .durationLimit
        }
        if durationExceeded {
            return .durationLimit
        }
        if bytesExceeded {
            return .byteLimit
        }
        return nil
    }
}
