import Foundation

public struct PixelTraceSessionManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let pixelTraceVersion: String
    public let sessionId: String
    public let startedAt: Date
    public let startedAtUptimeNanos: UInt64
    public let timeZoneIdentifier: String
    public var frameCount: Int
    public var totalBytes: Int
    public var droppedFrameCount: Int
    public var skippedFrameCount: Int
    public var eventCount: Int
    public var stopReason: String?
    public var endedAt: Date?
    public let metadata: PixelTraceMetadata

    public init(
        schemaVersion: Int = 1,
        pixelTraceVersion: String,
        sessionId: String,
        startedAt: Date,
        startedAtUptimeNanos: UInt64,
        timeZoneIdentifier: String,
        frameCount: Int = 0,
        totalBytes: Int = 0,
        droppedFrameCount: Int = 0,
        skippedFrameCount: Int = 0,
        eventCount: Int = 0,
        stopReason: String? = nil,
        endedAt: Date? = nil,
        metadata: PixelTraceMetadata = .empty
    ) {
        self.schemaVersion = schemaVersion
        self.pixelTraceVersion = pixelTraceVersion
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.startedAtUptimeNanos = startedAtUptimeNanos
        self.timeZoneIdentifier = timeZoneIdentifier
        self.frameCount = frameCount
        self.totalBytes = totalBytes
        self.droppedFrameCount = droppedFrameCount
        self.skippedFrameCount = skippedFrameCount
        self.eventCount = eventCount
        self.stopReason = stopReason
        self.endedAt = endedAt
        self.metadata = metadata
    }
}
