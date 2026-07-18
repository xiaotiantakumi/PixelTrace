import Foundation
import PixelTraceCore

/// Filesystem-level operations across recording sessions (pruning and full deletion).
enum PixelTraceRecordingStore {
    /// Removes the oldest session directories so that, after a new session is added, the count
    /// stays within `retention.maxRetainedSessions`. Called before opening a new session.
    static func pruneOldSessions(
        configuration: PixelTraceConfiguration,
        fileManager: FileManager = .default
    ) {
        guard let root = try? PixelTraceSessionWriter.rootDirectory(
            for: configuration,
            fileManager: fileManager
        ) else { return }
        guard let subdirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let decoder = PixelTraceJSONCoding.makeDecoder()
        var entries: [PixelTraceSessionDirectoryEntry] = []
        for directory in subdirectories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let manifestURL = directory.appendingPathComponent("session.json", isDirectory: false)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(PixelTraceSessionManifest.self, from: data) else {
                continue
            }
            entries.append(PixelTraceSessionDirectoryEntry(
                directoryName: directory.lastPathComponent,
                startedAt: manifest.startedAt,
                totalBytes: manifest.totalBytes
            ))
        }

        let toDelete = PixelTraceSessionPruning.entriesToDelete(
            entries,
            maxSessionCount: max(0, configuration.retention.maxRetainedSessions - 1)
        )
        for entry in toDelete {
            let url = root.appendingPathComponent(entry.directoryName, isDirectory: true)
            try? fileManager.removeItem(at: url)
        }
    }

    /// Removes every recording session under the configured root.
    static func deleteAll(
        configuration: PixelTraceConfiguration,
        fileManager: FileManager = .default
    ) throws {
        let root = try PixelTraceSessionWriter.rootDirectory(for: configuration, fileManager: fileManager)
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }
}
