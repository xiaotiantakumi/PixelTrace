import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

final class PixelTraceNetworkLoggingTests: XCTestCase {
    private func readNetworkPayload(root: URL, sessionId: String) throws -> PixelTraceNetworkPayload? {
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        let url = try PixelTraceSessionWriter
            .sessionDirectory(sessionId: sessionId, configuration: config)
            .appendingPathComponent("events.jsonl")
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = PixelTraceJSONCoding.makeDecoder()
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            if case let .network(_, payload) = try decoder.decode(PixelTraceTimelineEvent.self, from: Data(line.utf8)) {
                return payload
            }
        }
        return nil
    }

    private func waitForEvents(_ minimum: Int) async {
        for _ in 0..<50 {
            if await (PixelTrace.currentManifest()?.eventCount ?? 0) >= minimum { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testNetworkEventMasksHeadersStripsQueryAndDropsBody() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        // Default redaction: captureBodies == false.
        PixelTrace.setEnabled(true)
        PixelTrace.configure(config)
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "net-1"))

        PixelTrace.logNetworkEvent(PixelTraceNetworkEvent(
            endpoint: "/v1/messages?token=secret",
            method: "POST",
            statusCode: 200,
            latencyMs: 42,
            requestHeaders: ["Authorization": "Bearer xyz", "Content-Type": "application/json"],
            responseBodyPreview: "should not be stored",
            metadata: ["service": "example"]
        ))
        await waitForEvents(1)

        let payload = try readNetworkPayload(root: root, sessionId: "net-1")
        let unwrapped = try XCTUnwrap(payload)
        XCTAssertEqual(unwrapped.endpoint, "/v1/messages")
        XCTAssertEqual(unwrapped.requestHeaders?["Authorization"], "***")
        XCTAssertEqual(unwrapped.requestHeaders?["Content-Type"], "application/json")
        XCTAssertNil(unwrapped.responseBodyPreview)
        XCTAssertEqual(unwrapped.method, "POST")
        XCTAssertEqual(unwrapped.statusCode, 200)

        await PixelTrace.endSession()
    }

    func testConvenienceOverloadCapturesBodyWhenEnabled() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        var redaction = PixelTraceNetworkRedaction.default
        redaction.captureBodies = true
        config.network = redaction
        PixelTrace.setEnabled(true)
        PixelTrace.configure(config)
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "net-2"))

        PixelTrace.logNetworkEvent(
            endpoint: "/health",
            method: "GET",
            statusCode: 204,
            bodyPreview: "ok"
        )
        await waitForEvents(1)

        let payload = try XCTUnwrap(readNetworkPayload(root: root, sessionId: "net-2"))
        XCTAssertEqual(payload.endpoint, "/health")
        XCTAssertEqual(payload.responseBodyPreview, "ok")

        await PixelTrace.endSession()
    }
}
