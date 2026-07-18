import CoreImage
import CoreVideo
import Foundation
import ImageIO
import os
import PixelTraceCore

/// Writes one recording session to one directory.
///
/// The capture thread calls `submit(_:)`, which returns immediately; JPEG encoding and disk
/// I/O run on a detached `.utility` task. When in-flight writes exceed `maxPendingWrites` the
/// frame is dropped (counted, never blocking) — the recorder is an instrument and must not
/// stall the host's real-time frame processing (spec §3.2).
actor PixelTraceSessionWriter {
    private let directory: URL
    private let fileManager: FileManager
    private let startedAt: Date
    private let configuration: PixelTraceConfiguration
    private nonisolated let maxPendingWrites: Int
    private let sessionId: String

    private var frameCount = 0
    private var totalBytes = 0
    private var droppedFrameCount = 0
    private var skippedFrameCount = 0
    private var eventCount = 0
    private var ciContext: CIContext?
    private var manifest: PixelTraceSessionManifest
    private(set) var limitStopReason: PixelTraceLimitStopReason?
    private var manifestStopReason: PixelTraceStopReason?

    init(
        sessionId: String,
        startedAt: Date,
        uptimeNanos: UInt64,
        directory: URL,
        configuration: PixelTraceConfiguration,
        metadata: PixelTraceMetadata
    ) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.directory = directory
        self.configuration = configuration
        self.maxPendingWrites = max(1, configuration.maxPendingWrites)
        self.fileManager = .default
        self.manifest = PixelTraceSessionManifest(
            pixelTraceVersion: PixelTracePackageVersion.current,
            sessionId: sessionId,
            startedAt: startedAt,
            startedAtUptimeNanos: uptimeNanos,
            timeZoneIdentifier: TimeZone.current.identifier,
            metadata: metadata
        )
    }

    // MARK: - Directory resolution

    static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches
            .appendingPathComponent("PixelTrace", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    static func rootDirectory(
        for configuration: PixelTraceConfiguration,
        fileManager: FileManager = .default
    ) throws -> URL {
        if let root = configuration.rootDirectory {
            return root
        }
        return try defaultRootDirectory(fileManager: fileManager)
    }

    static func sessionDirectory(
        sessionId: String,
        configuration: PixelTraceConfiguration,
        fileManager: FileManager = .default
    ) throws -> URL {
        try rootDirectory(for: configuration, fileManager: fileManager)
            .appendingPathComponent(sessionId, isDirectory: true)
    }

    nonisolated var directoryPath: String { directory.path }

    // MARK: - Lifecycle

    var isStopped: Bool { manifestStopReason != nil }

    func currentManifest() -> PixelTraceSessionManifest { manifest }

    /// Creates the session directory and writes the initial manifest.
    func begin() {
        guard ensureDirectoryExists() else { return }
        applyBackupExclusion()
        writeManifest()
        configuration.observer?.pixelTraceDidBeginSession(
            PixelTraceObservedSession(
                sessionId: sessionId,
                directoryPath: directory.path,
                startedAt: startedAt,
                metadata: manifest.metadata
            )
        )
    }

    // MARK: - Frame submission (backpressure)

    private struct SubmitState {
        var nextSequence = 0
        var pendingWriteCount = 0
    }

    private nonisolated let submitLock = OSAllocatedUnfairLock(initialState: SubmitState())

    /// Returns immediately. Drops the frame (counted) when in-flight writes are saturated.
    nonisolated func submit(_ frame: PixelTraceFrame) {
        enum Decision {
            case write(sequence: Int)
            case drop
        }

        let decision = submitLock.withLock { state -> Decision in
            if state.pendingWriteCount >= maxPendingWrites {
                return .drop
            }
            let sequence = state.nextSequence
            state.nextSequence += 1
            state.pendingWriteCount += 1
            return .write(sequence: sequence)
        }

        switch decision {
        case .write(let sequence):
            Task.detached(priority: .utility) { [self] in
                await writeFrame(frame, sequence: sequence)
                submitLock.withLock { $0.pendingWriteCount -= 1 }
            }
        case .drop:
            Task.detached(priority: .utility) { [self] in
                await recordDroppedFrame()
            }
        }
    }

    /// Encodes and writes a single frame plus its sidecar. Awaitable for deterministic tests.
    func writeFrame(_ frame: PixelTraceFrame, sequence: Int) async {
        guard !isStopped else { return }
        guard ensureDirectoryExists() else { return }

        let elapsed = frame.capturedAt.timeIntervalSince(startedAt)
        if let reason = PixelTraceLimitEvaluator.stopReason(
            elapsed: elapsed,
            totalBytes: totalBytes,
            limits: configuration.limits
        ) {
            stopDueToLimit(reason)
            return
        }

        let basename = PixelTraceFrameNaming.basename(sequence: sequence)
        let ext = configuration.frameEncoder?.fileExtension ?? "jpg"
        let frameURL = directory.appendingPathComponent("\(basename).\(ext)", isDirectory: false)
        let jsonURL = directory.appendingPathComponent("\(basename).json", isDirectory: false)

        let frameData: Data?
        if let encoder = configuration.frameEncoder {
            frameData = encoder.encode(frame.pixelBuffer, orientation: frame.orientation)
        } else {
            frameData = renderJPEG(frame)
        }
        guard let frameData else { return }
        guard writeFile(frameData, to: frameURL) else { return }

        let pixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        let sidecar = PixelTraceFrameSidecar(
            sequence: sequence,
            capturedAt: frame.capturedAt,
            orientation: PixelTraceOrientationMapping.label(for: frame.orientation),
            orientationRawValue: frame.orientation.rawValue,
            pixelFormat: FourCCFormatting.string(from: pixelFormat),
            pixelFormatRawValue: pixelFormat,
            pixelWidth: CVPixelBufferGetWidth(frame.pixelBuffer),
            pixelHeight: CVPixelBufferGetHeight(frame.pixelBuffer),
            jpegBytes: frameData.count,
            metadata: frame.metadata
        )
        guard let jsonData = try? PixelTraceJSONCoding.makeEncoder().encode(sidecar) else { return }
        guard writeFile(jsonData, to: jsonURL) else { return }

        frameCount += 1
        totalBytes += frameData.count + jsonData.count
        manifest.frameCount = frameCount
        manifest.totalBytes = totalBytes
        writeManifest()

        configuration.observer?.pixelTraceDidWriteFrame(
            PixelTraceObservedFrame(
                sessionId: sessionId,
                sequence: sequence,
                fileURL: frameURL,
                encodedData: frameData,
                byteCount: frameData.count,
                capturedAt: frame.capturedAt
            )
        )

        if let reason = PixelTraceLimitEvaluator.stopReason(
            elapsed: elapsed,
            totalBytes: totalBytes,
            limits: configuration.limits
        ) {
            stopDueToLimit(reason)
        }
    }

    // MARK: - Counters

    /// Records a frame the host intentionally skipped (host-side thinning).
    func recordSkippedFrame() {
        guard !isStopped else { return }
        skippedFrameCount += 1
        manifest.skippedFrameCount = skippedFrameCount
        writeManifest()
    }

    /// Records a frame dropped by backpressure (recorder saturation).
    func recordDroppedFrame() {
        droppedFrameCount += 1
        manifest.droppedFrameCount = droppedFrameCount
        writeManifest()
    }

    // MARK: - Timeline events

    /// Appends one timeline event as a JSON Lines record to `events.jsonl`.
    func appendEvent(_ event: PixelTraceTimelineEvent) {
        guard !isStopped else { return }
        guard ensureDirectoryExists() else { return }
        guard let line = try? PixelTraceJSONCoding.makeEncoder().encode(event) else { return }
        let url = directory.appendingPathComponent("events.jsonl", isDirectory: false)
        appendLine(line, to: url)
        eventCount += 1
        manifest.eventCount = eventCount
        writeManifest()
    }

    private func appendLine(_ data: Data, to url: URL) {
        var payload = data
        payload.append(0x0A) // newline

        if fileManager.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            writeFile(payload, to: url)
        }
    }

    // MARK: - Stop

    func stopByUser() { finalize(stopReason: .userStopped) }
    func stopBySessionEnded() { finalize(stopReason: .sessionEnded) }
    func stopDisabled() { finalize(stopReason: .disabled) }

    private func stopDueToLimit(_ reason: PixelTraceLimitStopReason) {
        limitStopReason = reason
        let manifestReason: PixelTraceStopReason = reason == .durationLimit ? .durationLimit : .byteLimit
        finalize(stopReason: manifestReason)
    }

    private func finalize(stopReason: PixelTraceStopReason) {
        guard manifestStopReason == nil else { return }
        manifestStopReason = stopReason
        manifest.stopReason = stopReason.rawValue
        manifest.endedAt = Date()
        writeManifest()
        configuration.observer?.pixelTraceDidEndSession(
            PixelTraceObservedSessionEnd(
                sessionId: sessionId,
                directoryPath: directory.path,
                frameCount: frameCount,
                totalBytes: totalBytes,
                stopReason: stopReason,
                endedAt: manifest.endedAt ?? Date()
            )
        )
    }

    // MARK: - Status

    func makeStatus() -> PixelTraceStatus {
        PixelTraceStatus(
            sessionId: sessionId,
            directoryPath: directory.path,
            isRecording: manifestStopReason == nil,
            frameCount: frameCount,
            totalBytes: totalBytes,
            droppedFrameCount: droppedFrameCount,
            skippedFrameCount: skippedFrameCount,
            startedAt: startedAt,
            endedAt: manifest.endedAt,
            stopReason: manifestStopReason
        )
    }

    // MARK: - Rendering & IO

    private func renderJPEG(_ frame: PixelTraceFrame) -> Data? {
        PixelTraceJPEGRenderer.renderJPEG(
            pixelBuffer: frame.pixelBuffer,
            orientation: frame.orientation,
            maxLongEdge: configuration.jpegMaxLongEdge,
            quality: configuration.jpegQuality,
            context: sharedCIContext()
        )
    }

    private func sharedCIContext() -> CIContext {
        if let ciContext {
            return ciContext
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        ciContext = context
        return context
    }

    @discardableResult
    private func writeFile(_ data: Data, to url: URL) -> Bool {
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: configuration.fileProtection]
        return fileManager.createFile(atPath: url.path, contents: data, attributes: attributes)
        #else
        return fileManager.createFile(atPath: url.path, contents: data)
        #endif
    }

    private func writeManifest() {
        guard let data = try? PixelTraceJSONCoding.makeEncoder().encode(manifest) else { return }
        let url = directory.appendingPathComponent("session.json", isDirectory: false)
        try? data.write(to: url, options: .atomic)
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: configuration.fileProtection],
            ofItemAtPath: url.path
        )
        #endif
    }

    private func applyBackupExclusion() {
        guard configuration.excludeFromBackup else { return }
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    @discardableResult
    private func ensureDirectoryExists() -> Bool {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
