import Foundation
import os
import PixelTraceCore

/// The package version stamped into each manifest.
enum PixelTracePackageVersion {
    static let current = "0.1.0"
}

/// Public facade for enabling recording, managing sessions, and submitting frames.
///
/// Release safety is two-fold (spec §7.3): `defaultEnabled` is false in Release, and every
/// implementation body below is wrapped in `#if DEBUG` so the capture/IO machinery is not
/// compiled into a Release binary. The public signatures still exist in Release, so host call
/// sites compile unchanged regardless of build configuration.
public enum PixelTrace {

    // MARK: - Enablement

    /// True in DEBUG builds, false in Release builds.
    public static let defaultEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    #if DEBUG
    private static let enabledLock = OSAllocatedUnfairLock(initialState: PixelTrace.defaultEnabled)
    private static let configurationLock = OSAllocatedUnfairLock(initialState: PixelTraceConfiguration.default)
    private static let writerLock = OSAllocatedUnfairLock<PixelTraceSessionWriter?>(initialState: nil)
    #endif

    /// The current enabled state. Always false in Release.
    public static var isEnabled: Bool {
        #if DEBUG
        return enabledLock.withLock { $0 }
        #else
        return false
        #endif
    }

    /// Toggles recording. Disabling finalizes the in-progress session. No-op in Release.
    public static func setEnabled(_ enabled: Bool) {
        #if DEBUG
        let wasEnabled = enabledLock.withLock { state -> Bool in
            let previous = state
            state = enabled
            return previous
        }
        if wasEnabled, !enabled {
            let writer = writerLock.withLock { current -> PixelTraceSessionWriter? in
                let value = current
                current = nil
                return value
            }
            if let writer {
                Task { await writer.stopDisabled() }
            }
        }
        #endif
    }

    // MARK: - Configuration

    /// Applies configuration and the initial enabled state. Intended to be called once at launch.
    public static func configure(_ configuration: PixelTraceConfiguration) {
        #if DEBUG
        configurationLock.withLock { $0 = configuration }
        enabledLock.withLock { $0 = configuration.initiallyEnabled }
        #endif
    }

    // MARK: - Sessions

    /// Starts a new recording session, finalizing any in-progress session and pruning old
    /// sessions beyond the retention limit first.
    public static func beginSession(_ context: PixelTraceSessionContext) async {
        #if DEBUG
        guard isEnabled else { return }
        await endSession()

        let configuration = configurationLock.withLock { $0 }
        PixelTraceRecordingStore.pruneOldSessions(configuration: configuration)

        guard let directory = try? PixelTraceSessionWriter.sessionDirectory(
            sessionId: context.sessionId,
            configuration: configuration
        ) else { return }

        let writer = PixelTraceSessionWriter(
            sessionId: context.sessionId,
            startedAt: context.startedAt,
            uptimeNanos: PixelTraceClock.now().uptimeNanos,
            directory: directory,
            configuration: configuration,
            metadata: context.metadata
        )
        await writer.begin()
        writerLock.withLock { $0 = writer }
        #endif
    }

    /// Ends and finalizes the in-progress session.
    public static func endSession() async {
        #if DEBUG
        let writer = writerLock.withLock { current -> PixelTraceSessionWriter? in
            let value = current
            current = nil
            return value
        }
        guard let writer else { return }
        await writer.stopBySessionEnded()
        #endif
    }

    // MARK: - Frame submission

    /// Submits one frame. Returns immediately. Silently ignored when disabled, when there is no
    /// active session, or when backpressure is saturated.
    public static func submit(_ frame: PixelTraceFrame) {
        #if DEBUG
        guard isEnabled else { return }
        guard let writer = writerLock.withLock({ $0 }) else { return }
        writer.submit(frame)
        #endif
    }

    /// Notifies the recorder that the host intentionally skipped a frame (host-side thinning),
    /// so it can be counted separately from backpressure drops (spec §5.4).
    public static func recordSkippedFrame() {
        #if DEBUG
        guard isEnabled else { return }
        guard let writer = writerLock.withLock({ $0 }) else { return }
        Task { await writer.recordSkippedFrame() }
        #endif
    }

    // MARK: - Timeline events

    /// Appends a tap event to the session timeline (spec §9). No-op in Release.
    public static func logTap(_ event: PixelTraceTapEvent) {
        #if DEBUG
        appendTimelineEvent(.tap(timestamp: event.timestamp, payload: event.payload))
        #endif
    }

    /// Appends an arbitrary named marker to the session timeline (e.g. a "reproduce bug"
    /// button). No-op in Release.
    public static func logMarker(_ name: String, metadata: PixelTraceMetadata = .empty) {
        #if DEBUG
        appendTimelineEvent(.marker(
            timestamp: Date(),
            payload: PixelTraceMarkerPayload(name: name, metadata: metadata)
        ))
        #endif
    }

    /// Appends a network event to the session timeline, applying the configured redaction
    /// (known auth headers masked, query strings stripped, bodies dropped unless
    /// `captureBodies` is enabled). No-op in Release.
    public static func logNetworkEvent(_ event: PixelTraceNetworkEvent) {
        #if DEBUG
        let redaction = configurationLock.withLock { $0.network }
        let payload = PixelTraceNetworkPayload(
            endpoint: redaction.sanitizedEndpoint(event.endpoint),
            method: event.method,
            statusCode: event.statusCode,
            latencyMs: event.latencyMs,
            requestHeaders: redaction.redactedHeaders(event.requestHeaders),
            responseHeaders: redaction.redactedHeaders(event.responseHeaders),
            requestBodyPreview: redaction.bodyPreview(event.requestBodyPreview),
            responseBodyPreview: redaction.bodyPreview(event.responseBodyPreview),
            error: event.error,
            metadata: event.metadata
        )
        appendTimelineEvent(.network(timestamp: event.timestamp, payload: payload))
        #endif
    }

    #if DEBUG
    private static func appendTimelineEvent(_ event: PixelTraceTimelineEvent) {
        guard isEnabled else { return }
        guard let writer = writerLock.withLock({ $0 }) else { return }
        Task { await writer.appendEvent(event) }
    }
    #endif

    // MARK: - Status

    /// A snapshot of the current recording state, or nil when there is no session.
    public static func currentStatus() async -> PixelTraceStatus? {
        #if DEBUG
        guard let writer = writerLock.withLock({ $0 }) else { return nil }
        return await writer.makeStatus()
        #else
        return nil
        #endif
    }

    /// The current manifest, or nil when there is no session.
    public static func currentManifest() async -> PixelTraceSessionManifest? {
        #if DEBUG
        guard let writer = writerLock.withLock({ $0 }) else { return nil }
        return await writer.currentManifest()
        #else
        return nil
        #endif
    }

    // MARK: - Deletion

    /// Deletes all stored recording sessions. Finalizes any in-progress session first.
    public static func deleteAllRecordings() async throws {
        #if DEBUG
        let writer = writerLock.withLock { current -> PixelTraceSessionWriter? in
            let value = current
            current = nil
            return value
        }
        if let writer {
            await writer.stopByUser()
        }
        let configuration = configurationLock.withLock { $0 }
        try PixelTraceRecordingStore.deleteAll(configuration: configuration)
        #endif
    }
}
