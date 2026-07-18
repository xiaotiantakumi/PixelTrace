import Foundation
import XCTest
import PixelTrace
import PixelTraceCore

/// These exercise the process-global facade. Each test uses its own temporary root and
/// re-enables recording in setUp so ordering does not leak state.
final class PixelTraceFacadeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PixelTrace.setEnabled(true)
    }

    private func configureTempRoot() -> URL {
        let root = makeTestTempDirectory()
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        PixelTrace.configure(config)
        return root
    }

    func testDefaultEnabledIsTrueInDebug() {
        // The test bundle is built in debug configuration.
        XCTAssertTrue(PixelTrace.defaultEnabled)
    }

    func testSessionLifecycle() async throws {
        let root = configureTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(PixelTrace.isEnabled)

        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "facade-1"))
        let status = await PixelTrace.currentStatus()
        XCTAssertEqual(status?.sessionId, "facade-1")
        XCTAssertEqual(status?.isRecording, true)

        // submit returns immediately and must not crash.
        PixelTrace.submit(PixelTraceFrame(pixelBuffer: makeTestPixelBuffer(), orientation: .up))

        await PixelTrace.endSession()
        let after = await PixelTrace.currentStatus()
        XCTAssertNil(after)
    }

    func testSetEnabledFalseClearsSession() async throws {
        let root = configureTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "facade-2"))
        let running = await PixelTrace.currentStatus()
        XCTAssertNotNil(running)

        PixelTrace.setEnabled(false)
        XCTAssertFalse(PixelTrace.isEnabled)
        let cleared = await PixelTrace.currentStatus()
        XCTAssertNil(cleared)

        PixelTrace.setEnabled(true)
    }

    func testDeleteAllViaFacade() async throws {
        let root = configureTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        await PixelTrace.beginSession(PixelTraceSessionContext(sessionId: "facade-3"))
        try await PixelTrace.deleteAllRecordings()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let afterDelete = await PixelTrace.currentStatus()
        XCTAssertNil(afterDelete)
    }
}
