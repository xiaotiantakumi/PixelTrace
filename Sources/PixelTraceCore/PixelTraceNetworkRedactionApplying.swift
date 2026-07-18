import Foundation

/// Pure masking operations applied to network events before they are written (spec §11.2).
extension PixelTraceNetworkRedaction {
    /// Replaces the value of any header whose key (compared case-insensitively) is in
    /// `redactedKeys` with `redactionPlaceholder`.
    public func redactedHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers else { return nil }
        var result: [String: String] = [:]
        result.reserveCapacity(headers.count)
        for (key, value) in headers {
            result[key] = redactedKeys.contains(key.lowercased()) ? redactionPlaceholder : value
        }
        return result
    }

    /// Returns the body preview only when `captureBodies` is true, truncated to
    /// `maxBodyPreviewBytes` UTF-8 bytes. Returns nil otherwise (privacy default).
    public func bodyPreview(_ body: String?) -> String? {
        guard captureBodies, let body else { return nil }
        let utf8 = body.utf8
        guard utf8.count > max(0, maxBodyPreviewBytes) else { return body }
        let prefixBytes = utf8.prefix(max(0, maxBodyPreviewBytes))
        return String(decoding: prefixBytes, as: UTF8.self)
    }

    /// Drops any query string, keeping only the path portion. Defensive: the host is expected to
    /// pass a path already, but a query is stripped here regardless.
    public func sanitizedEndpoint(_ endpoint: String) -> String {
        guard let index = endpoint.firstIndex(of: "?") else { return endpoint }
        return String(endpoint[..<index])
    }
}
