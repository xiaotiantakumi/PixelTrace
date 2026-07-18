import Foundation

public enum PixelTraceLimitStopReason: String, Sendable, Codable {
    case durationLimit
    case byteLimit
}

public enum PixelTraceStopReason: String, Sendable, Codable {
    case userStopped
    case durationLimit
    case byteLimit
    case sessionEnded
    case disabled
}
