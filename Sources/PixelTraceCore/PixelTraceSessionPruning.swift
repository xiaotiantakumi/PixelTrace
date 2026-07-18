import Foundation

public struct PixelTraceSessionDirectoryEntry: Equatable, Sendable {
    public let directoryName: String
    public let startedAt: Date
    public let totalBytes: Int

    public init(directoryName: String, startedAt: Date, totalBytes: Int) {
        self.directoryName = directoryName
        self.startedAt = startedAt
        self.totalBytes = totalBytes
    }
}

public enum PixelTraceSessionPruning {
    public static func entriesToDelete(
        _ entries: [PixelTraceSessionDirectoryEntry],
        maxSessionCount: Int
    ) -> [PixelTraceSessionDirectoryEntry] {
        let sorted = entries.sorted { $0.startedAt < $1.startedAt }

        if maxSessionCount <= 0 {
            return sorted
        }

        var remaining = sorted
        var removed: [PixelTraceSessionDirectoryEntry] = []

        while remaining.count > maxSessionCount {
            let entry = remaining.removeFirst()
            removed.append(entry)
        }

        return removed
    }
}
