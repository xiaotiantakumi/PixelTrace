import Foundation
import PixelTraceCore

/// Observes session lifecycle and frame writes from the recorder actor.
public protocol PixelTraceObserving: Sendable {
    func pixelTraceDidBeginSession(_ session: PixelTraceObservedSession)
    func pixelTraceDidWriteFrame(_ frame: PixelTraceObservedFrame)
    func pixelTraceDidEndSession(_ summary: PixelTraceObservedSessionEnd)
}

public struct PixelTraceObservedSession: Sendable {
    public let sessionId: String
    public let directoryPath: String
    public let startedAt: Date
    public let metadata: PixelTraceMetadata

    public init(
        sessionId: String,
        directoryPath: String,
        startedAt: Date,
        metadata: PixelTraceMetadata
    ) {
        self.sessionId = sessionId
        self.directoryPath = directoryPath
        self.startedAt = startedAt
        self.metadata = metadata
    }
}

public struct PixelTraceObservedFrame: Sendable {
    public let sessionId: String
    public let sequence: Int
    public let fileURL: URL
    public let encodedData: Data
    public let byteCount: Int
    public let capturedAt: Date

    public init(
        sessionId: String,
        sequence: Int,
        fileURL: URL,
        encodedData: Data,
        byteCount: Int,
        capturedAt: Date
    ) {
        self.sessionId = sessionId
        self.sequence = sequence
        self.fileURL = fileURL
        self.encodedData = encodedData
        self.byteCount = byteCount
        self.capturedAt = capturedAt
    }
}

public struct PixelTraceObservedSessionEnd: Sendable {
    public let sessionId: String
    public let directoryPath: String
    public let frameCount: Int
    public let totalBytes: Int
    public let stopReason: PixelTraceStopReason
    public let endedAt: Date

    public init(
        sessionId: String,
        directoryPath: String,
        frameCount: Int,
        totalBytes: Int,
        stopReason: PixelTraceStopReason,
        endedAt: Date
    ) {
        self.sessionId = sessionId
        self.directoryPath = directoryPath
        self.frameCount = frameCount
        self.totalBytes = totalBytes
        self.stopReason = stopReason
        self.endedAt = endedAt
    }
}
