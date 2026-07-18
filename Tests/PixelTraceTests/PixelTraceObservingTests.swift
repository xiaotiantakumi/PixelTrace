import Foundation
import os
import XCTest
@testable import PixelTrace
import PixelTraceCore

private final class ObserverRecorder: PixelTraceObserving, @unchecked Sendable {
    enum Callback: Equatable {
        case begin(sessionId: String)
        case frame(sessionId: String, sequence: Int)
        case end(sessionId: String, stopReason: PixelTraceStopReason)
    }

    private let lock = OSAllocatedUnfairLock(initialState: [Callback]())

    func pixelTraceDidBeginSession(_ session: PixelTraceObservedSession) {
        lock.withLock { $0.append(.begin(sessionId: session.sessionId)) }
    }

    func pixelTraceDidWriteFrame(_ frame: PixelTraceObservedFrame) {
        lock.withLock { $0.append(.frame(sessionId: frame.sessionId, sequence: frame.sequence)) }
    }

    func pixelTraceDidEndSession(_ summary: PixelTraceObservedSessionEnd) {
        lock.withLock { $0.append(.end(sessionId: summary.sessionId, stopReason: summary.stopReason)) }
    }

    func callbacks() -> [Callback] {
        lock.withLock { $0 }
    }
}

final class PixelTraceObservingTests: XCTestCase {
    func testObserverReceivesBeginFrameEndInOrder() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = ObserverRecorder()
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.observer = recorder

        let directory = try PixelTraceSessionWriter.sessionDirectory(sessionId: "obs-1", configuration: config)
        let writer = PixelTraceSessionWriter(
            sessionId: "obs-1",
            startedAt: Date(),
            uptimeNanos: 1,
            directory: directory,
            configuration: config,
            metadata: .empty
        )
        await writer.begin()

        let frame = PixelTraceFrame(
            pixelBuffer: makeTestPixelBuffer(),
            orientation: .up,
            capturedAt: Date()
        )
        await writer.writeFrame(frame, sequence: 0)
        await writer.stopBySessionEnded()

        XCTAssertEqual(recorder.callbacks(), [
            .begin(sessionId: "obs-1"),
            .frame(sessionId: "obs-1", sequence: 0),
            .end(sessionId: "obs-1", stopReason: .sessionEnded),
        ])
    }
}
