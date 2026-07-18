import XCTest
@testable import PixelTraceCore

final class PixelTraceSessionPruningTests: XCTestCase {
    private func entry(_ name: String, day: Int, bytes: Int = 0) -> PixelTraceSessionDirectoryEntry {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: day))!
        return PixelTraceSessionDirectoryEntry(directoryName: name, startedAt: date, totalBytes: bytes)
    }

    func testEmpty() {
        XCTAssertTrue(PixelTraceSessionPruning.entriesToDelete([], maxSessionCount: 5).isEmpty)
    }

    func testUnderLimit() {
        let entries = [entry("a", day: 1), entry("b", day: 2)]
        XCTAssertTrue(PixelTraceSessionPruning.entriesToDelete(entries, maxSessionCount: 5).isEmpty)
    }

    func testOverLimitRemovesOldest() {
        let entries = [
            entry("c", day: 3),
            entry("a", day: 1),
            entry("b", day: 2),
        ]
        // maxSessionCount is the number to KEEP; 3 entries keeping 1 deletes the 2 oldest.
        let deleted = PixelTraceSessionPruning.entriesToDelete(entries, maxSessionCount: 1)
        XCTAssertEqual(deleted.map(\.directoryName), ["a", "b"])
    }

    func testMaxSessionCountZeroReturnsAllSortedAscending() {
        let entries = [
            entry("c", day: 3),
            entry("a", day: 1),
            entry("b", day: 2),
        ]
        let deleted = PixelTraceSessionPruning.entriesToDelete(entries, maxSessionCount: 0)
        XCTAssertEqual(deleted.map(\.directoryName), ["a", "b", "c"])
    }
}
