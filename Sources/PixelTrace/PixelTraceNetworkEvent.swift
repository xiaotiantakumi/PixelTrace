import Foundation
import PixelTraceCore

/// A network event recorded to the session timeline (spec §4.5, §11).
///
/// The host passes a path (without query) as `endpoint`; PixelTrace strips any query string
/// defensively and masks known auth headers. Bodies are only recorded when the configured
/// redaction has `captureBodies == true`.
public struct PixelTraceNetworkEvent: Sendable {
    public var endpoint: String
    public var method: String?
    public var statusCode: Int?
    public var latencyMs: Double?
    public var requestHeaders: [String: String]?
    public var responseHeaders: [String: String]?
    public var requestBodyPreview: String?
    public var responseBodyPreview: String?
    public var error: String?
    public var timestamp: Date
    public var metadata: PixelTraceMetadata

    public init(
        endpoint: String,
        method: String? = nil,
        statusCode: Int? = nil,
        latencyMs: Double? = nil,
        requestHeaders: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        requestBodyPreview: String? = nil,
        responseBodyPreview: String? = nil,
        error: String? = nil,
        timestamp: Date = Date(),
        metadata: PixelTraceMetadata = .empty
    ) {
        self.endpoint = endpoint
        self.method = method
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestBodyPreview = requestBodyPreview
        self.responseBodyPreview = responseBodyPreview
        self.error = error
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

extension PixelTrace {
    /// Convenience for the common call site. `bodyPreview` maps to the response body preview and
    /// is only retained when the configured redaction has `captureBodies == true`.
    public static func logNetworkEvent(
        endpoint: String,
        method: String? = nil,
        statusCode: Int? = nil,
        latencyMs: Double? = nil,
        bodyPreview: String? = nil,
        metadata: PixelTraceMetadata = .empty
    ) {
        logNetworkEvent(PixelTraceNetworkEvent(
            endpoint: endpoint,
            method: method,
            statusCode: statusCode,
            latencyMs: latencyMs,
            responseBodyPreview: bodyPreview,
            metadata: metadata
        ))
    }
}
