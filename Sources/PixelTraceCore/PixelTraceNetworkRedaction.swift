import Foundation

public struct PixelTraceNetworkRedaction: Sendable, Equatable {
    public var redactedKeys: Set<String>
    public var maxBodyPreviewBytes: Int
    public var captureBodies: Bool
    public var redactionPlaceholder: String

    public init(
        redactedKeys: Set<String> = Self.defaultRedactedKeys,
        maxBodyPreviewBytes: Int = 2048,
        captureBodies: Bool = false,
        redactionPlaceholder: String = "***"
    ) {
        self.redactedKeys = redactedKeys
        self.maxBodyPreviewBytes = maxBodyPreviewBytes
        self.captureBodies = captureBodies
        self.redactionPlaceholder = redactionPlaceholder
    }

    public static let `default` = PixelTraceNetworkRedaction()

    public static let defaultRedactedKeys: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "api-key",
        "apikey",
        "x-auth-token",
        "authentication",
        "bearer",
    ]
}
