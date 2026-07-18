import Foundation

public enum PixelTraceTimelineEventType: String, Codable, Sendable {
    case tap
    case network
    case marker
}

public struct PixelTraceTapPayload: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var windowWidth: Double
    public var windowHeight: Double
    public var screen: String?
    public var phase: String
    public var metadata: PixelTraceMetadata

    public init(
        x: Double,
        y: Double,
        windowWidth: Double,
        windowHeight: Double,
        screen: String? = nil,
        phase: String,
        metadata: PixelTraceMetadata = .empty
    ) {
        self.x = x
        self.y = y
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.screen = screen
        self.phase = phase
        self.metadata = metadata
    }
}

public struct PixelTraceNetworkPayload: Codable, Equatable, Sendable {
    public var endpoint: String
    public var method: String?
    public var statusCode: Int?
    public var latencyMs: Double?
    public var requestHeaders: [String: String]?
    public var responseHeaders: [String: String]?
    public var requestBodyPreview: String?
    public var responseBodyPreview: String?
    public var error: String?
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
        self.metadata = metadata
    }
}

public struct PixelTraceMarkerPayload: Codable, Equatable, Sendable {
    public var name: String
    public var metadata: PixelTraceMetadata

    public init(name: String, metadata: PixelTraceMetadata = .empty) {
        self.name = name
        self.metadata = metadata
    }
}

public enum PixelTraceTimelineEvent: Equatable, Sendable, Codable {
    case tap(timestamp: Date, payload: PixelTraceTapPayload)
    case network(timestamp: Date, payload: PixelTraceNetworkPayload)
    case marker(timestamp: Date, payload: PixelTraceMarkerPayload)

    public var timestamp: Date {
        switch self {
        case .tap(let timestamp, _), .network(let timestamp, _), .marker(let timestamp, _):
            return timestamp
        }
    }

    public var type: PixelTraceTimelineEventType {
        switch self {
        case .tap: return .tap
        case .network: return .network
        case .marker: return .marker
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PixelTraceTimelineEventType.self, forKey: .type)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)

        switch type {
        case .tap:
            let payload = try container.decode(PixelTraceTapPayload.self, forKey: .payload)
            self = .tap(timestamp: timestamp, payload: payload)
        case .network:
            let payload = try container.decode(PixelTraceNetworkPayload.self, forKey: .payload)
            self = .network(timestamp: timestamp, payload: payload)
        case .marker:
            let payload = try container.decode(PixelTraceMarkerPayload.self, forKey: .payload)
            self = .marker(timestamp: timestamp, payload: payload)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)

        switch self {
        case .tap(_, let payload):
            try container.encode(payload, forKey: .payload)
        case .network(_, let payload):
            try container.encode(payload, forKey: .payload)
        case .marker(_, let payload):
            try container.encode(payload, forKey: .payload)
        }
    }
}
