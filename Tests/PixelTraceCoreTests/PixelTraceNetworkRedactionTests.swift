import XCTest
@testable import PixelTraceCore

final class PixelTraceNetworkRedactionTests: XCTestCase {
    func testDefaultValues() {
        let redaction = PixelTraceNetworkRedaction.default
        XCTAssertEqual(redaction.maxBodyPreviewBytes, 2048)
        XCTAssertFalse(redaction.captureBodies)
        XCTAssertEqual(redaction.redactionPlaceholder, "***")
        XCTAssertTrue(redaction.redactedKeys.contains("authorization"))
        XCTAssertTrue(redaction.redactedKeys.contains("set-cookie"))
    }

    func testRedactedHeadersMasksKnownKeysCaseInsensitively() {
        let redaction = PixelTraceNetworkRedaction.default
        let masked = redaction.redactedHeaders([
            "Authorization": "Bearer secret",
            "X-API-Key": "abc123",
            "Content-Type": "application/json",
        ])
        XCTAssertEqual(masked?["Authorization"], "***")
        XCTAssertEqual(masked?["X-API-Key"], "***")
        XCTAssertEqual(masked?["Content-Type"], "application/json")
    }

    func testRedactedHeadersNilPassesThrough() {
        XCTAssertNil(PixelTraceNetworkRedaction.default.redactedHeaders(nil))
    }

    func testBodyPreviewDroppedByDefault() {
        let redaction = PixelTraceNetworkRedaction.default
        XCTAssertNil(redaction.bodyPreview("some body"))
    }

    func testBodyPreviewCapturedWhenEnabled() {
        var redaction = PixelTraceNetworkRedaction.default
        redaction.captureBodies = true
        XCTAssertEqual(redaction.bodyPreview("hello"), "hello")
    }

    func testBodyPreviewTruncatesToByteLimit() {
        var redaction = PixelTraceNetworkRedaction.default
        redaction.captureBodies = true
        redaction.maxBodyPreviewBytes = 4
        XCTAssertEqual(redaction.bodyPreview("abcdefg"), "abcd")
    }

    func testSanitizedEndpointStripsQuery() {
        let redaction = PixelTraceNetworkRedaction.default
        XCTAssertEqual(redaction.sanitizedEndpoint("/v1/messages?token=abc"), "/v1/messages")
        XCTAssertEqual(redaction.sanitizedEndpoint("/v1/messages"), "/v1/messages")
    }
}
