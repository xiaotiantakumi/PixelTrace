import CoreGraphics
import Foundation
import PixelTraceCore

/// A tap observed by the host, recorded to the session timeline (spec §4.5, §9).
public struct PixelTraceTapEvent: Sendable {
    public enum Phase: String, Sendable, Codable {
        case down
        case up
    }

    /// Location in window coordinates.
    public var location: CGPoint
    /// The window size at the time of the tap, used to normalize the location across devices.
    public var windowSize: CGSize
    /// Optional host-provided screen identifier (e.g. a root view name).
    public var screen: String?
    public var phase: Phase
    public var timestamp: Date
    public var metadata: PixelTraceMetadata

    public init(
        location: CGPoint,
        windowSize: CGSize,
        screen: String? = nil,
        phase: Phase = .down,
        timestamp: Date = Date(),
        metadata: PixelTraceMetadata = .empty
    ) {
        self.location = location
        self.windowSize = windowSize
        self.screen = screen
        self.phase = phase
        self.timestamp = timestamp
        self.metadata = metadata
    }

    /// The serializable payload written to `events.jsonl`.
    var payload: PixelTraceTapPayload {
        PixelTraceTapPayload(
            x: Double(location.x),
            y: Double(location.y),
            windowWidth: Double(windowSize.width),
            windowHeight: Double(windowSize.height),
            screen: screen,
            phase: phase.rawValue,
            metadata: metadata
        )
    }
}
