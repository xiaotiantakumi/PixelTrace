import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

final class PixelTraceCustomNetworkRedactorTests: XCTestCase {
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

    func testCustomNetworkRedactorSkipsBuiltInMasking() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.customNetworkRedactor = { event in
            var rewritten = event
            rewritten.endpoint = "/custom/path"
            rewritten.requestHeaders = event.requestHeaders
            return rewritten
        }

        PixelTrace.setEnabled(true)
        PixelTrace.configure(config)
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "redact-custom"))

        PixelTrace.logNetworkEvent(PixelTraceNetworkEvent(
            endpoint: "/v1/messages?token=secret",
            method: "POST",
            requestHeaders: ["Authorization": "Bearer xyz"]
        ))
        await waitForEvents(1)

        let payload = try XCTUnwrap(readNetworkPayload(root: root, sessionId: "redact-custom"))
        XCTAssertEqual(payload.endpoint, "/custom/path")
        XCTAssertEqual(payload.requestHeaders?["Authorization"], "Bearer xyz")

        await PixelTrace.endSession()
    }

    func testNilCustomNetworkRedactorAppliesBuiltInMasking() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.customNetworkRedactor = nil

        PixelTrace.setEnabled(true)
        PixelTrace.configure(config)
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "redact-default"))

        PixelTrace.logNetworkEvent(PixelTraceNetworkEvent(
            endpoint: "/v1/messages?token=secret",
            method: "POST",
            requestHeaders: ["Authorization": "Bearer xyz"]
        ))
        await waitForEvents(1)

        let payload = try XCTUnwrap(readNetworkPayload(root: root, sessionId: "redact-default"))
        XCTAssertEqual(payload.endpoint, "/v1/messages")
        XCTAssertEqual(payload.requestHeaders?["Authorization"], "***")

        await PixelTrace.endSession()
    }
}
