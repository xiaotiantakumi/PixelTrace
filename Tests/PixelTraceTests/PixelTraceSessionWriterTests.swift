import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

final class PixelTraceSessionWriterTests: XCTestCase {
    private func makeConfig(root: URL, limits: PixelTraceLimits = .default) -> PixelTraceConfiguration {
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.limits = limits
        // Force software rendering path is not needed; native context works headless on macOS.
        return config
    }

    private func makeWriter(
        sessionId: String,
        startedAt: Date,
        config: PixelTraceConfiguration,
        metadata: PixelTraceMetadata = .empty
    ) throws -> PixelTraceSessionWriter {
        let directory = try PixelTraceSessionWriter.sessionDirectory(sessionId: sessionId, configuration: config)
        return PixelTraceSessionWriter(
            sessionId: sessionId,
            startedAt: startedAt,
            uptimeNanos: 42,
            directory: directory,
            configuration: config,
            metadata: metadata
        )
    }

    func testBeginWritesInitialManifest() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = makeConfig(root: root)
        let writer = try makeWriter(sessionId: "s1", startedAt: Date(), config: config)
        await writer.begin()

        let manifestURL = try PixelTraceSessionWriter
            .sessionDirectory(sessionId: "s1", configuration: config)
            .appendingPathComponent("session.json")
        let manifest = try PixelTraceJSONCoding.makeDecoder()
            .decode(PixelTraceSessionManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(manifest.sessionId, "s1")
        XCTAssertEqual(manifest.frameCount, 0)
        XCTAssertEqual(manifest.startedAtUptimeNanos, 42)
        XCTAssertEqual(manifest.pixelTraceVersion, "0.1.0")
        XCTAssertNil(manifest.stopReason)
    }

    func testWriteFrameProducesFilesAndUpdatesManifest() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = makeConfig(root: root)
        let writer = try makeWriter(sessionId: "s1", startedAt: Date(), config: config)
        await writer.begin()

        let frame = PixelTraceFrame(
            pixelBuffer: makeTestPixelBuffer(width: 100, height: 60),
            orientation: .right,
            capturedAt: Date(),
            metadata: ["k": "v"]
        )
        await writer.writeFrame(frame, sequence: 0)

        let dir = try PixelTraceSessionWriter.sessionDirectory(sessionId: "s1", configuration: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("frame_000000.jpg").path))
        let jsonURL = dir.appendingPathComponent("frame_000000.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))

        let sidecar = try PixelTraceJSONCoding.makeDecoder()
            .decode(PixelTraceFrameSidecar.self, from: Data(contentsOf: jsonURL))
        XCTAssertEqual(sidecar.sequence, 0)
        XCTAssertEqual(sidecar.orientation, "right")
        XCTAssertEqual(sidecar.orientationRawValue, 6)
        // Sidecar records the native buffer dimensions, independent of orientation.
        XCTAssertEqual(sidecar.pixelWidth, 100)
        XCTAssertEqual(sidecar.pixelHeight, 60)
        XCTAssertGreaterThan(sidecar.jpegBytes, 0)
        XCTAssertEqual(sidecar.metadata.values["k"], .string("v"))

        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.frameCount, 1)
        XCTAssertGreaterThan(manifest.totalBytes, 0)
    }

    func testFramesUseZeroPaddedSequentialNames() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = makeConfig(root: root)
        let writer = try makeWriter(sessionId: "s1", startedAt: Date(), config: config)
        await writer.begin()
        for sequence in 0..<3 {
            await writer.writeFrame(
                PixelTraceFrame(pixelBuffer: makeTestPixelBuffer(), orientation: .up),
                sequence: sequence
            )
        }
        let dir = try PixelTraceSessionWriter.sessionDirectory(sessionId: "s1", configuration: config)
        for name in ["frame_000000.jpg", "frame_000001.jpg", "frame_000002.jpg"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path), name)
        }
        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.frameCount, 3)
    }

    func testDurationLimitStopsBeforeWriting() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date()
        let config = makeConfig(root: root, limits: PixelTraceLimits(maxDuration: 1, maxTotalBytes: 500 * 1024 * 1024))
        let writer = try makeWriter(sessionId: "s1", startedAt: start, config: config)
        await writer.begin()

        let frame = PixelTraceFrame(
            pixelBuffer: makeTestPixelBuffer(),
            orientation: .up,
            capturedAt: start.addingTimeInterval(2)
        )
        await writer.writeFrame(frame, sequence: 0)

        let stopped = await writer.isStopped
        XCTAssertTrue(stopped)
        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.stopReason, PixelTraceStopReason.durationLimit.rawValue)
        XCTAssertNotNil(manifest.endedAt)
        XCTAssertEqual(manifest.frameCount, 0)
    }

    func testByteLimitStopsAfterWriting() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date()
        let config = makeConfig(root: root, limits: PixelTraceLimits(maxDuration: 600, maxTotalBytes: 10))
        let writer = try makeWriter(sessionId: "s1", startedAt: start, config: config)
        await writer.begin()

        await writer.writeFrame(
            PixelTraceFrame(pixelBuffer: makeTestPixelBuffer(), orientation: .up, capturedAt: start),
            sequence: 0
        )
        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.frameCount, 1)
        XCTAssertEqual(manifest.stopReason, PixelTraceStopReason.byteLimit.rawValue)
    }

    func testDroppedAndSkippedCounters() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = makeConfig(root: root)
        let writer = try makeWriter(sessionId: "s1", startedAt: Date(), config: config)
        await writer.begin()
        await writer.recordDroppedFrame()
        await writer.recordDroppedFrame()
        await writer.recordSkippedFrame()
        let manifest = await writer.currentManifest()
        XCTAssertEqual(manifest.droppedFrameCount, 2)
        XCTAssertEqual(manifest.skippedFrameCount, 1)
    }

    func testMakeStatusReflectsState() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = makeConfig(root: root)
        let writer = try makeWriter(sessionId: "s1", startedAt: Date(), config: config)
        await writer.begin()
        await writer.writeFrame(
            PixelTraceFrame(pixelBuffer: makeTestPixelBuffer(), orientation: .up),
            sequence: 0
        )
        let status = await writer.makeStatus()
        XCTAssertEqual(status.sessionId, "s1")
        XCTAssertTrue(status.isRecording)
        XCTAssertEqual(status.frameCount, 1)
        XCTAssertNil(status.stopReason)

        await writer.stopBySessionEnded()
        let stopped = await writer.makeStatus()
        XCTAssertFalse(stopped.isRecording)
        XCTAssertEqual(stopped.stopReason, .sessionEnded)
    }
}
