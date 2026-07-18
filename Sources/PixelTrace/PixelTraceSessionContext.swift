import Foundation
import PixelTraceCore

/// Metadata the host supplies when starting a session.
public struct PixelTraceSessionContext: Sendable {
    public var sessionId: String
    public var startedAt: Date
    /// Free-form host metadata (capture preset, buffer dimensions, app version, etc.).
    public var metadata: PixelTraceMetadata

    public init(
        sessionId: String = UUID().uuidString,
        startedAt: Date = Date(),
        metadata: PixelTraceMetadata = .empty
    ) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.metadata = metadata
    }
}
