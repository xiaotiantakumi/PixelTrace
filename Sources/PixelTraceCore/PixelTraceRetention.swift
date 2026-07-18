import Foundation

public struct PixelTraceRetention: Sendable, Equatable {
    public var maxRetainedSessions: Int

    public init(maxRetainedSessions: Int = 5) {
        self.maxRetainedSessions = maxRetainedSessions
    }

    public static let `default` = PixelTraceRetention()
}
