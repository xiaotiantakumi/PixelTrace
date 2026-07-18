import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

/// Proves the unified millisecond ISO8601 serialization (spec §10.2) is applied across every
/// on-disk artifact: session.json, frame sidecars, and events.jsonl. It scans the raw files for
/// any date-time token and asserts each one carries the canonical `.SSSZ` suffix.
final class PixelTraceSerializationConsistencyTests: XCTestCase {
    /// Matches a date-time prefix, capturing the millisecond+Z suffix when present.
    private let dateTokenPattern = "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{3}Z)?"

    private func assertAllDatesAreCanonical(
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let regex = try! NSRegularExpression(pattern: dateTokenPattern)
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        XCTAssertGreaterThan(matches.count, 0, "no date tokens found", file: file, line: line)
        for match in matches {
            let msGroup = match.range(at: 1)
            XCTAssertNotEqual(
                msGroup.location, NSNotFound,
                "found a date without the canonical .SSSZ suffix",
                file: file,
                line: line
            )
            // The captured token must also parse via the shared clock.
            if let whole = Range(match.range, in: text) {
                XCTAssertNotNil(
                    PixelTraceClock.date(from: String(text[whole])),
                    "date token does not parse via PixelTraceClock",
                    file: file,
                    line: line
                )
            }
        }
    }

    func testManifestSidecarAndEventsShareCanonicalDateFormat() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        let sessionId = "serial-1"
        let directory = try PixelTraceSessionWriter.sessionDirectory(sessionId: sessionId, configuration: config)
        let writer = PixelTraceSessionWriter(
            sessionId: sessionId,
            startedAt: Date(),
            uptimeNanos: 7,
            directory: directory,
            configuration: config,
            metadata: ["appVersion": "1.0.0"]
        )
        await writer.begin()
        await writer.writeFrame(
            PixelTraceFrame(pixelBuffer: makeTestPixelBuffer(), orientation: .right, capturedAt: Date()),
            sequence: 0
        )
        await writer.appendEvent(.tap(
            timestamp: Date(),
            payload: PixelTraceTapPayload(x: 1, y: 2, windowWidth: 10, windowHeight: 20, phase: "down")
        ))
        await writer.appendEvent(.network(
            timestamp: Date(),
            payload: PixelTraceNetworkPayload(endpoint: "/e", metadata: .empty)
        ))
        await writer.appendEvent(.marker(
            timestamp: Date(),
            payload: PixelTraceMarkerPayload(name: "m")
        ))
        await writer.stopBySessionEnded()

        let manifestText = try String(contentsOf: directory.appendingPathComponent("session.json"), encoding: .utf8)
        let sidecarText = try String(contentsOf: directory.appendingPathComponent("frame_000000.json"), encoding: .utf8)
        let eventsText = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)

        // Manifest carries startedAt AND endedAt; both must be canonical.
        XCTAssertTrue(manifestText.contains("\"startedAt\""))
        XCTAssertTrue(manifestText.contains("\"endedAt\""))
        assertAllDatesAreCanonical(in: manifestText)
        assertAllDatesAreCanonical(in: sidecarText)
        assertAllDatesAreCanonical(in: eventsText)

        // events.jsonl must be one event per line.
        let eventLines = eventsText.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(eventLines.count, 3)
    }
}
