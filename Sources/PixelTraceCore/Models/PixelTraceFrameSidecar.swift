import Foundation

public struct PixelTraceFrameSidecar: Codable, Equatable, Sendable {
    public let sequence: Int
    public let capturedAt: Date
    public let orientation: String
    public let orientationRawValue: UInt32
    public let pixelFormat: String
    public let pixelFormatRawValue: UInt32
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let jpegBytes: Int
    public let metadata: PixelTraceMetadata

    public init(
        sequence: Int,
        capturedAt: Date,
        orientation: String,
        orientationRawValue: UInt32,
        pixelFormat: String,
        pixelFormatRawValue: UInt32,
        pixelWidth: Int,
        pixelHeight: Int,
        jpegBytes: Int,
        metadata: PixelTraceMetadata = .empty
    ) {
        self.sequence = sequence
        self.capturedAt = capturedAt
        self.orientation = orientation
        self.orientationRawValue = orientationRawValue
        self.pixelFormat = pixelFormat
        self.pixelFormatRawValue = pixelFormatRawValue
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.jpegBytes = jpegBytes
        self.metadata = metadata
    }
}
