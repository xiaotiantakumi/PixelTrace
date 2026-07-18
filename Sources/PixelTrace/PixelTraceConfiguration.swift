import CoreGraphics
import Foundation
import PixelTraceCore

/// Package-wide configuration. Intended to be set once at app launch via `PixelTrace.configure(_:)`.
public struct PixelTraceConfiguration: @unchecked Sendable {
    /// Storage root. When nil, `<container>/Library/Caches/PixelTrace/recordings` is used.
    public var rootDirectory: URL?
    public var limits: PixelTraceLimits
    public var retention: PixelTraceRetention
    /// JPEG compression quality. Default 0.8.
    public var jpegQuality: CGFloat
    /// Native-resolution ceiling. Default 3840 (4K at 1:1; only above this is the frame scaled down).
    public var jpegMaxLongEdge: CGFloat
    /// Backpressure ceiling for in-flight writes. Default 4. Frames beyond this are dropped
    /// (counted in `droppedFrameCount`) rather than blocking the capture thread.
    public var maxPendingWrites: Int
    public var network: PixelTraceNetworkRedaction
    /// Initial enabled state. Defaults to `PixelTrace.defaultEnabled`.
    public var initiallyEnabled: Bool
    /// Whether to mark the recording directory excluded from backups. Default true (spec §12).
    public var excludeFromBackup: Bool
    /// File protection applied to written files (applied on iOS; a no-op elsewhere). Default `.complete`.
    public var fileProtection: FileProtectionType

    public init(
        rootDirectory: URL? = nil,
        limits: PixelTraceLimits = .default,
        retention: PixelTraceRetention = .default,
        jpegQuality: CGFloat = 0.8,
        jpegMaxLongEdge: CGFloat = 3840,
        maxPendingWrites: Int = 4,
        network: PixelTraceNetworkRedaction = .default,
        initiallyEnabled: Bool = PixelTrace.defaultEnabled,
        excludeFromBackup: Bool = true,
        fileProtection: FileProtectionType = .complete
    ) {
        self.rootDirectory = rootDirectory
        self.limits = limits
        self.retention = retention
        self.jpegQuality = jpegQuality
        self.jpegMaxLongEdge = jpegMaxLongEdge
        self.maxPendingWrites = maxPendingWrites
        self.network = network
        self.initiallyEnabled = initiallyEnabled
        self.excludeFromBackup = excludeFromBackup
        self.fileProtection = fileProtection
    }

    public static let `default` = PixelTraceConfiguration()
}
