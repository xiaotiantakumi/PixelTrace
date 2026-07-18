import CoreGraphics
import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

final class PixelTraceTimelineTests: XCTestCase {
    private func makeWriter(root: URL, sessionId: String = "s1") throws -> PixelTraceSessionWriter {
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        let directory = try PixelTraceSessionWriter.sessionDirectory(sessionId: sessionId, configuration: config)
        return PixelTraceSessionWriter(
            sessionId: sessionId,
            startedAt: Date(),
            uptimeNanos: 1,
            directory: directory,
            configuration: config,
            metadata: .empty
        )
    }

    private func eventsURL(root: URL, sessionId: String = "s1") throws -> URL {
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        return try PixelTraceSessionWriter
            .sessionDirectory(sessionId: sessionId, configuration: config)
            .appendingPathComponent("events.jsonl")
    }

    func testAppendEventWritesJSONLines() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try makeWriter(root: root)
        await writer.begin()

        await writer.appendEvent(.tap(
            timestamp: Date(),
            payload: PixelTraceTapPayload(x: 10, y: 20, windowWidth: 393, windowHeight: 852, phase: "down")
        ))
        await writer.appendEvent(.marker(
            timestamp: Date(),
            payload: PixelTraceMarkerPayload(name: "checkpoint", metadata: ["note": "here"])
        ))

        let url = try eventsURL(root: root)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)

        let decoder = PixelTraceJSONCoding.makeDecoder()
        let first = try decoder.decode(PixelTraceTimelineEvent.self, from: Data(lines[0].utf8))
        let second = try decoder.decode(PixelTraceTimelineEvent.self, from: Data(lines[1].utf8))
        XCTAssertEqual(first.type, .tap)
        XCTAssertEqual(second.type, .marker)

        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.eventCount, 2)
    }

    func testAppendEventIgnoredAfterStop() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try makeWriter(root: root)
        await writer.begin()
        await writer.stopBySessionEnded()
        await writer.appendEvent(.marker(timestamp: Date(), payload: PixelTraceMarkerPayload(name: "late")))
        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.eventCount, 0)
    }

    func testTapEventPayloadMapping() {
        let event = PixelTraceTapEvent(
            location: CGPoint(x: 12.5, y: 34.0),
            windowSize: CGSize(width: 320, height: 640),
            screen: "root",
            phase: .up,
            metadata: ["k": 1]
        )
        let payload = event.payload
        XCTAssertEqual(payload.x, 12.5)
        XCTAssertEqual(payload.y, 34.0)
        XCTAssertEqual(payload.windowWidth, 320)
        XCTAssertEqual(payload.windowHeight, 640)
        XCTAssertEqual(payload.screen, "root")
        XCTAssertEqual(payload.phase, "up")
        XCTAssertEqual(payload.metadata.values["k"], .int(1))
    }

    func testFacadeLogMarkerAndTapReachTimeline() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        PixelTrace.setEnabled(true)
        PixelTrace.configure(config)
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "timeline-1"))

        PixelTrace.logMarker("bug", metadata: ["x": 1])
        PixelTrace.logTap(PixelTraceTapEvent(
            location: CGPoint(x: 1, y: 2),
            windowSize: CGSize(width: 100, height: 200)
        ))

        // The facade forwards to the writer on a Task; poll the manifest until both land.
        var eventCount = 0
        for _ in 0..<50 {
            eventCount = await PixelTrace.currentManifest()?.eventCount ?? 0
            if eventCount >= 2 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(eventCount, 2)

        await PixelTrace.endSession()
    }
}
