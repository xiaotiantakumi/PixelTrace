import Foundation
import PixelTraceCore

/// A snapshot of the current recording state, suitable for UI polling.
public struct PixelTraceStatus: Sendable {
    public let sessionId: String?
    public let directoryPath: String?
    public let isRecording: Bool
    public let frameCount: Int
    public let totalBytes: Int
    public let droppedFrameCount: Int
    public let skippedFrameCount: Int
    public let startedAt: Date?
    public let endedAt: Date?
    public let stopReason: PixelTraceStopReason?

    public init(
        sessionId: String?,
        directoryPath: String?,
        isRecording: Bool,
        frameCount: Int,
        totalBytes: Int,
        droppedFrameCount: Int,
        skippedFrameCount: Int,
        startedAt: Date?,
        endedAt: Date?,
        stopReason: PixelTraceStopReason?
    ) {
        self.sessionId = sessionId
        self.directoryPath = directoryPath
        self.isRecording = isRecording
        self.frameCount = frameCount
        self.totalBytes = totalBytes
        self.droppedFrameCount = droppedFrameCount
        self.skippedFrameCount = skippedFrameCount
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stopReason = stopReason
    }
}
