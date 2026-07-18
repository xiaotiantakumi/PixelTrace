import XCTest
@testable import PixelTraceCore

final class PixelTraceModelCodingTests: XCTestCase {
    private let encoder = PixelTraceJSONCoding.makeEncoder()
    private let decoder = PixelTraceJSONCoding.makeDecoder()

    private func isoDate(day: Int = 18, ms: Int = 3) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 7
        components.day = day
        components.hour = 4
        components.minute = 11
        components.second = 0
        components.nanosecond = ms * 1_000_000
        let raw = calendar.date(from: components)!
        // Normalize to the canonical millisecond serialization precision (§10.2) so that
        // encode→decode round-trip equality is exact (sub-ms precision is dropped by design).
        return PixelTraceClock.date(from: PixelTraceClock.string(from: raw))!
    }

    func testSessionManifestRoundTrip() throws {
        let manifest = PixelTraceSessionManifest(
            pixelTraceVersion: "0.1.0",
            sessionId: "session-1",
            startedAt: isoDate(),
            startedAtUptimeNanos: 81234567890123,
            timeZoneIdentifier: "Asia/Tokyo",
            frameCount: 118,
            totalBytes: 214450176,
            stopReason: PixelTraceStopReason.sessionEnded.rawValue,
            endedAt: isoDate(ms: 512),
            metadata: ["actualPreset": "hd4k", "appVersion": "1.4.0"]
        )

        let data = try encoder.encode(manifest)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"startedAt\":\"2026-07-18T04:11:00.003Z\""))
        XCTAssertTrue(json.contains("\"endedAt\":\"2026-07-18T04:11:00.512Z\""))
        XCTAssertTrue(json.contains("\"droppedFrameCount\":0"))

        let decoded = try decoder.decode(PixelTraceSessionManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }

    func testFrameSidecarRoundTrip() throws {
        let sidecar = PixelTraceFrameSidecar(
            sequence: 42,
            capturedAt: isoDate(ms: 271),
            orientation: "right",
            orientationRawValue: 6,
            pixelFormat: "420f",
            pixelFormatRawValue: 875704422,
            pixelWidth: 3840,
            pixelHeight: 2160,
            jpegBytes: 1863402,
            metadata: ["changeScore": 0.42, "recognizedCharCount": 412]
        )

        let data = try encoder.encode(sidecar)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"capturedAt\":\"2026-07-18T04:11:00.271Z\""))
        XCTAssertTrue(json.contains("\"pixelFormat\":\"420f\""))

        let decoded = try decoder.decode(PixelTraceFrameSidecar.self, from: data)
        XCTAssertEqual(decoded, sidecar)
    }

    func testEncodedKeysAreSorted() throws {
        let manifest = PixelTraceSessionManifest(
            pixelTraceVersion: "0.1.0",
            sessionId: "session-1",
            startedAt: isoDate(),
            startedAtUptimeNanos: 1,
            timeZoneIdentifier: "UTC"
        )
        let data = try encoder.encode(manifest)
        let json = String(decoding: data, as: UTF8.self)
        let droppedIndex = json.range(of: "\"droppedFrameCount\"")!.lowerBound
        let frameCountIndex = json.range(of: "\"frameCount\"")!.lowerBound
        let schemaIndex = json.range(of: "\"schemaVersion\"")!.lowerBound
        XCTAssertLessThan(droppedIndex, frameCountIndex)
        XCTAssertLessThan(frameCountIndex, schemaIndex)
    }
}
