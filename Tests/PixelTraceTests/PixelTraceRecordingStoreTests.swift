import Foundation
import XCTest
@testable import PixelTrace
import PixelTraceCore

final class PixelTraceRecordingStoreTests: XCTestCase {
    private func seedSession(
        id: String,
        startedAt: Date,
        config: PixelTraceConfiguration
    ) async throws {
        let directory = try PixelTraceSessionWriter.sessionDirectory(sessionId: id, configuration: config)
        let writer = PixelTraceSessionWriter(
            sessionId: id,
            startedAt: startedAt,
            uptimeNanos: 1,
            directory: directory,
            configuration: config,
            metadata: .empty
        )
        await writer.begin()
    }

    func testPruneKeepsNewestWithinRetention() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.retention = PixelTraceRetention(maxRetainedSessions: 2)

        let base = Date()
        try await seedSession(id: "s1", startedAt: base.addingTimeInterval(0), config: config)
        try await seedSession(id: "s2", startedAt: base.addingTimeInterval(10), config: config)
        try await seedSession(id: "s3", startedAt: base.addingTimeInterval(20), config: config)

        // Called before opening a new session, so it keeps (maxRetained - 1) = 1 → only newest.
        PixelTraceRecordingStore.pruneOldSessions(configuration: config)

        let exists: (String) throws -> Bool = { id in
            let dir = try PixelTraceSessionWriter.sessionDirectory(sessionId: id, configuration: config)
            return FileManager.default.fileExists(atPath: dir.path)
        }
        XCTAssertFalse(try exists("s1"))
        XCTAssertFalse(try exists("s2"))
        XCTAssertTrue(try exists("s3"))
    }

    func testPruneNoOpWhenUnderLimit() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        config.retention = PixelTraceRetention(maxRetainedSessions: 5)

        try await seedSession(id: "s1", startedAt: Date(), config: config)
        PixelTraceRecordingStore.pruneOldSessions(configuration: config)

        let dir = try PixelTraceSessionWriter.sessionDirectory(sessionId: "s1", configuration: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testDeleteAllRemovesRoot() async throws {
        let root = makeTestTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = PixelTraceConfiguration()
        config.rootDirectory = root
        try await seedSession(id: "s1", startedAt: Date(), config: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))

        try PixelTraceRecordingStore.deleteAll(configuration: config)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
