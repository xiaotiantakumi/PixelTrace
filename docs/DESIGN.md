# PixelTrace Design Document

This document lays out the design rationale, architecture, data formats, and API surface of PixelTrace: an on-device, real-footage debug recording library for iOS apps whose main screen is a live camera preview (OCR readers, document scanners, real-time image recognition, translation cameras, and similar).

For installation and a quick-start example, see the [README](../README.md).

---

## 1. Overview, purpose, and non-goals

### 1.1 What this package solves

PixelTrace is a reusable Swift Package that leaves an on-device debug recording of real camera footage for iOS apps whose main screen is a live camera preview.

Apps of this kind — where bugs frequently depend on exactly what the camera was seeing — share a recurring diagnostic problem: text gets garbled, a tracked object slips out of frame, recognition wobbles with lighting changes. Problems like these can't be root-caused after the fact unless the actual frame the pipeline processed can be inspected later.

PixelTrace writes the same `CVPixelBuffer` that the app's video pipeline is already processing out to a timeline on-device. Because the recorded artifact is the literal input to the pipeline — not a re-composited approximation of the screen — the recording functions as an instrument that reflects the real cause of a bug, rather than a guess at it.

This design was first implemented and proven through production use inside a private iOS app that keeps a camera feed on-screen continuously. PixelTrace reconstructs that implementation as a general-purpose library, with the host app's domain-specific concepts factored out into a generic, opaque metadata slot that any host can fill in with its own data.

### 1.2 Goals

- Record raw camera pixel buffers to disk on-device, per frame, as a JPEG plus a sidecar JSON, together with a manifest for the whole recording session.
- Append tap positions, network events, and arbitrary markers to the same session's timeline as structured events.
- Let recorded frames and the host app's own logs be correlated against a shared time reference.
- Record by default in DEBUG builds; disable the recording machinery itself in Release builds.
- Enforce two tiers of storage limits (within a session, and across sessions), plus an explicit "delete everything" action.
- Stay addable to any project independently: zero external dependencies (Apple frameworks only), and no public symbol name collisions.

### 1.3 Non-goals

- **Not a general-purpose screen recorder.** No view-hierarchy snapshotting either (see §2 for why).
- **Not a logging framework.** PixelTrace does not own log content; it only provides a shared time convention and helpers to correlate logs with recorded frames (§10).
- **No automatic network interception.** No global `URLSession` method swizzling (§11, §1.4).
- **No automatic upload.** Everything stays on-device; nothing is sent externally (§12).
- **No crash reporting, performance measurement, or analytics.**
- **Not intended for measurement in Release builds.** PixelTrace is a development-time debugging instrument.

### 1.4 Why a third-party session-replay SDK was not adopted

Before building this library, a view-hierarchy-snapshot-based session-replay SDK was evaluated and rejected, for three reasons.

First, that class of screen recording relies on `UIWindow.drawHierarchy(in:afterScreenUpdates:)`-style view-hierarchy snapshotting, which can only render hardware-composited layers such as `AVCaptureVideoPreviewLayer` as black or blank (the technical reason is covered in §2). For an app where the camera preview occupies nearly the whole screen, that means the one thing most worth debugging is exactly what fails to record.

Second, that SDK's network visualization relied on globally swizzling network-request completion callbacks, carrying a moderate runtime risk of racing against a host's own completion handling, and cross-cutting side effects on every host app's networking path.

Third, it captured request and response bodies unmasked by default, up to a size cap. While authentication header values were masked separately, that leaves no protection for other sensitive content that might appear in bodies.

PixelTrace carries these lessons into its own design: a commitment to raw pixel buffer recording (§2), explicit-call network helpers instead of interception (§11), and header redaction paired with request/response body capture that defaults to off (§11).

---

## 2. Why view-hierarchy snapshots don't work for this class of app

### 2.1 Characteristics of the target app

PixelTrace is aimed at apps that process a `CVPixelBuffer` obtained from something like `AVCaptureVideoDataOutput` on every frame, and display that video across nearly the entire screen. Reading OCR, document scanning, real-time image recognition, and translation cameras all fit this shape. In these apps, the input buffer to the video pipeline is the central object of debugging interest.

There is room to apply this outside camera apps too — the input to §4's API is any `CVPixelBuffer` — but the design decisions in this document are made with camera-preview-dominant apps as the baseline case.

### 2.2 Why view-hierarchy snapshotting renders as black

It helps to separate out how an iOS screen actually gets composited.

Ordinary UIKit and SwiftUI views drawn by the app process are represented as a Core Animation layer tree, and most of them hold their `contents` via an in-process software drawing path. `drawHierarchy(in:afterScreenUpdates:)` and `CALayer.render(in:)` work by re-drawing that in-process-readable layer content into a given context.

`AVCaptureVideoPreviewLayer`, and Metal/OpenGL layers, are different: their content is backed by a hardware buffer (such as an IOSurface), and final on-screen compositing happens on the render server side. That content cannot be read back through the app process's software drawing path. As a result, `drawHierarchy` renders that layer's region as black or blank, because it has no content to draw through that path.

In other words, snapshotting a screen that includes a camera preview drops exactly the footage that mattered most. This isn't a bug in any particular implementation — it's a structural consequence of the boundary between hardware-composited layers and the software drawing path.

### 2.3 The approach PixelTrace takes instead

PixelTrace does not composite the screen at all. It takes the `CVPixelBuffer` the app is already feeding into its pipeline, directly, and encodes that to JPEG for recording.

This has two advantages. What gets recorded is the pipeline's actual input, not a re-composited approximation of the screen, so it maps directly to the causal chain of a bug. And because it has no dependency on UI layer compositing, it records correctly regardless of the app's view hierarchy or rendering approach.

The trade-off is that PixelTrace records the camera footage, not the UI drawn on top of it. UI-side interactions are captured separately as tap events (§9), correlated with frames by timestamp.

---

## 3. Architecture

```
+---------------------------------- Host App ------------------------------------+
|                                                                                 |
|  AVCaptureVideoDataOutput --> video pipeline (OCR / detection / etc.)          |
|           |  (the same CVPixelBuffer, forked off)                              |
|           v                                                                    |
|      PixelTrace.submit(PixelTraceFrame)      PixelTrace.logTap / logNetworkEvent|
|      PixelTrace.beginSession / endSession    (called explicitly from the host) |
|           |                                            |                       |
+-----------+--------------------------------------------+-----------------------+
            v                                            v
+---------------------------------- PixelTrace package ---------------------------+
|                                                                                 |
|  PixelTraceUI (SwiftUI + UIKit)                                                 |
|    +- PixelTraceRecordingIndicator  ... always-on recording indicator (REC)     |
|    +- PixelTraceSettingsSection     ... toggle / status / delete-all button     |
|    +- PixelTraceWindow / .pixelTraceTapLogging()  ... tap position log entry    |
|                                                                                 |
|  PixelTrace (Foundation + CoreVideo + CoreImage + os)                           |
|    +- enum PixelTrace                ... public facade (enable / session / submit) |
|    +- actor PixelTraceSessionWriter  ... writes one session to one directory    |
|    +- PixelTraceJPEGRenderer         ... CVPixelBuffer -> JPEG (orientation preserved) |
|                                                                                 |
|  PixelTraceCore (Foundation only)                                              |
|    +- Codable models (Manifest / FrameSidecar / TimelineEvent)                 |
|    +- PixelTraceLimits / PixelTraceRetention  ... pure limit/retention logic    |
|    +- PixelTraceSessionPruning       ... deletion candidate selection (pure)    |
|    +- PixelTraceFrameNaming          ... zero-padded sequence numbering         |
|    +- PixelTraceClock                ... time reference and ISO8601 serialization |
|                                                                                 |
+---------------------------------------------------------------------------------+
                            | writes to
                            v
   <container>/Library/Caches/PixelTrace/recordings/<session-id>/
     +- session.json          ... session manifest
     +- frame_000000.jpg      ... frame image (1:1 up to 4K / quality 0.8)
     +- frame_000000.json     ... frame sidecar
     +- frame_000001.jpg ...
     +- events.jsonl          ... tap / network / marker timeline
```

### 3.1 Three module layers

PixelTrace splits into three modules.

**PixelTraceCore**: a pure-logic layer that depends only on Foundation. It holds the Codable models, limit evaluation, deletion candidate selection, sequence naming, and time serialization. This layer's own target declares no dependency on CoreVideo or UIKit, and it is built for macOS as well as iOS — since UIKit isn't available on macOS, importing it here would break that build, so the compiler enforces that this layer stays independent of UI concerns. (CoreVideo itself is available on both platforms, so keeping it out of this layer is a design choice enforced by review and by PixelTraceCore's tests, not by a build failure.) `swift test` runs here without a simulator, so the decision logic can be verified quickly.

**PixelTrace**: the layer responsible for capture and disk I/O. It receives `CVPixelBuffer`s, encodes JPEG, writes to the session directory, and exposes the public facade.

**PixelTraceUI**: a layer of reusable SwiftUI and UIKit components — the recording indicator, settings section, and tap-position-logging entry points.

A host app depends only on the layers it needs. An app that builds its own settings UI can depend on `PixelTrace` alone; a process that only needs to reason about recording decisions can depend on `PixelTraceCore` alone.

### 3.2 A design where writing never blocks the main pipeline

`submit(_:)`, called from the video pipeline's thread, returns immediately. The actual JPEG encoding and disk I/O are handed off to a detached task at `.utility` priority. When the number of outstanding writes exceeds a limit (4 by default), new frames are dropped rather than blocking, and the number of dropped frames is recorded in the manifest.

This backpressure design carries over from a production implementation already proven under real-world load. A debugging instrument must never be allowed to slow down the very frame pipeline it exists to observe.

---

## 4. Public API

The following are Swift-level signatures. Every public symbol is either prefixed with `PixelTrace` or lives under the `enum PixelTrace` namespace, to avoid collisions with other packages (§13.3).

### 4.1 Facade

```swift
public enum PixelTrace {

    // MARK: Enablement

    /// true in DEBUG builds, false in Release builds. See §7.
    public static let defaultEnabled: Bool

    /// Current enabled state. Always returns false in Release (§7).
    public static var isEnabled: Bool { get }

    /// Toggles recording on or off. Disabling finalizes any in-progress session.
    /// No-op when called in Release (§7).
    public static func setEnabled(_ enabled: Bool)

    // MARK: Configuration

    /// Sets storage location, limits, JPEG quality, network masking, etc. in one call.
    /// Intended to be called once at app launch. Defaults apply if omitted (§6).
    public static func configure(_ configuration: PixelTraceConfiguration)

    // MARK: Session

    /// Starts a new recording session.
    /// Finalizes any in-progress session and prunes sessions beyond the retention limit before opening.
    public static func beginSession(_ context: PixelTraceSessionContext) async

    /// Ends and finalizes the in-progress session.
    public static func endSession() async

    // MARK: Frame submission

    /// Submits one frame. Returns immediately. Silently dropped when disabled,
    /// outside a session, or over the pending-write limit.
    public static func submit(_ frame: PixelTraceFrame)

    // MARK: Timeline events

    /// Appends a tap position event to the timeline (§9).
    public static func logTap(_ event: PixelTraceTapEvent)

    /// Appends a network event to the timeline (§11). Masking is applied.
    public static func logNetworkEvent(_ event: PixelTraceNetworkEvent)

    /// Appends an arbitrary marker to the timeline (e.g. a "reproduce bug" button).
    public static func logMarker(_ name: String, metadata: PixelTraceMetadata)

    // MARK: Intentional thinning

    /// Notifies PixelTrace that the host deliberately chose not to submit a frame
    /// (e.g. during a stable stretch), so it can still be counted in
    /// `skippedFrameCount` (§5.4) — distinct from frames dropped by backpressure.
    public static func recordSkippedFrame()

    // MARK: State access (for UI polling)

    /// A snapshot of the current recording state. nil if there is no active session.
    public static func currentStatus() async -> PixelTraceStatus?

    /// The current manifest. nil if there is no active session.
    public static func currentManifest() async -> PixelTraceSessionManifest?

    // MARK: Deletion

    /// Deletes every saved recording session. (Confirmation UI is the caller's responsibility — see §8.3.)
    public static func deleteAllRecordings() async throws
}
```

### 4.2 Frame input

```swift
/// A single frame's recording input.
///
/// Rationale for `@unchecked Sendable`: as long as this pixel buffer is held with a
/// strong reference, the pool will not recycle it, so its contents remain valid.
/// Consumers only ever access it through a single writer, never concurrently.
public struct PixelTraceFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let orientation: CGImagePropertyOrientation
    public let capturedAt: Date
    public let metadata: PixelTraceMetadata

    public init(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        capturedAt: Date = Date(),
        metadata: PixelTraceMetadata = .empty
    )
}
```

Pass the same `CGImagePropertyOrientation` here that you pass to Vision or any other consumer. The recorded JPEG is drawn in "the orientation the pipeline saw," so what a human reviews later matches what the pipeline actually analyzed (§5.2).

### 4.3 Host-defined metadata

PixelTrace has no knowledge of host-specific concepts. To let any frame or session carry arbitrary JSON-representable data, it provides a metadata type.

```swift
/// A value representable as JSON: number, boolean, string, array, object, or null.
public enum PixelTraceJSONValue: Sendable, Codable, Equatable,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([PixelTraceJSONValue])
    case object([String: PixelTraceJSONValue])
    case null
}

/// Host-defined metadata attached to a frame or session.
///
/// Two construction paths are provided: directly from a dictionary literal, and from
/// any Encodable value. Both end up serialized as a JSON object in the sidecar.
public struct PixelTraceMetadata: Sendable, Equatable {
    public static let empty: PixelTraceMetadata

    /// Builds from a key/value dictionary.
    public init(_ values: [String: PixelTraceJSONValue])

    /// Builds from any Encodable value (must encode to a top-level JSON object).
    public init<E: Encodable>(encoding value: E) throws
}

extension PixelTraceMetadata: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, PixelTraceJSONValue)...)
}
```

Building from a dictionary literal suits quickly attaching a handful of values:

```swift
let frame = PixelTraceFrame(
    pixelBuffer: buffer,
    orientation: .right,
    capturedAt: timestamp,
    metadata: [
        "sceneChangeScore": 0.42,
        "captureReason": "periodicSample",
        "detectedObjectCount": 128
    ]
)
```

Building from `Encodable` suits a host that already has a typed sidecar struct:

```swift
struct MyFrameNote: Encodable {
    let detectedLabel: String
    let confidence: Float
    let objectCount: Int
    let sceneChangeScore: Double?
}
let frame = PixelTraceFrame(
    pixelBuffer: buffer, orientation: .right, capturedAt: ts,
    metadata: try PixelTraceMetadata(encoding: note)
)
```

### 4.4 Session context and configuration

```swift
/// Metadata the host provides when starting a session.
public struct PixelTraceSessionContext: Sendable {
    public var sessionId: String          // defaults to a UUID
    public var startedAt: Date            // defaults to Date()
    /// Camera preset, buffer dimensions, app version, or anything else the host wants attached.
    public var metadata: PixelTraceMetadata

    public init(
        sessionId: String = UUID().uuidString,
        startedAt: Date = Date(),
        metadata: PixelTraceMetadata = .empty
    )
}

/// Package-wide configuration.
public struct PixelTraceConfiguration: Sendable {
    /// Storage root. Defaults to <container>/Library/Caches/PixelTrace/recordings.
    public var rootDirectory: URL?
    public var limits: PixelTraceLimits
    public var retention: PixelTraceRetention
    public var jpegQuality: CGFloat           // default 0.8
    public var jpegMaxLongEdge: CGFloat       // default 3840 (1:1 up to 4K; shrinks only above this)
    public var maxPendingWrites: Int          // default 4
    public var network: PixelTraceNetworkRedaction
    /// Initial enabled state. Defaults to PixelTrace.defaultEnabled.
    public var initiallyEnabled: Bool
    /// Whether to apply backup exclusion and file protection. Default true (§12).
    public var excludeFromBackup: Bool
    public var fileProtection: FileProtectionType   // default .complete

    public static let `default`: PixelTraceConfiguration
}

public struct PixelTraceLimits: Sendable {
    public var maxDuration: TimeInterval      // default 600 seconds
    public var maxTotalBytes: Int             // default 500 * 1024 * 1024
}

public struct PixelTraceRetention: Sendable {
    public var maxRetainedSessions: Int       // default 5
}
```

### 4.5 Timeline event types

```swift
public struct PixelTraceTapEvent: Sendable {
    public enum Phase: String, Sendable, Codable { case down, up }

    public var location: CGPoint          // window coordinate space
    public var windowSize: CGSize         // reference size for normalization
    public var screen: String?            // host-provided screen identifier (e.g. a route name); optional
    public var phase: Phase               // defaults to .down
    public var timestamp: Date            // defaults to Date()
    public var metadata: PixelTraceMetadata

    public init(location:windowSize:screen:phase:timestamp:metadata:)
}

public struct PixelTraceNetworkEvent: Sendable {
    public var endpoint: String           // path only; the host strips the query string (§11)
    public var method: String?
    public var statusCode: Int?
    public var latencyMs: Double?
    public var requestHeaders: [String: String]?    // masked by PixelTrace
    public var responseHeaders: [String: String]?   // masked by PixelTrace
    public var requestBodyPreview: String?          // saved only when captureBodies is true
    public var responseBodyPreview: String?
    public var error: String?
    public var timestamp: Date            // defaults to Date()
    public var metadata: PixelTraceMetadata

    public init(/* all defaulted; only endpoint is required */)
}

/// A lighter-weight convenience for callers.
extension PixelTrace {
    public static func logNetworkEvent(
        endpoint: String,
        method: String? = nil,
        statusCode: Int? = nil,
        latencyMs: Double? = nil,
        bodyPreview: String? = nil,
        metadata: PixelTraceMetadata = .empty
    )
}
```

### 4.6 Status and manifest access

```swift
public struct PixelTraceStatus: Sendable {
    public let sessionId: String?
    public let directoryPath: String?
    public let isRecording: Bool
    public let frameCount: Int
    public let totalBytes: Int
    public let droppedFrameCount: Int
    public let skippedFrameCount: Int
    public let startedAt: Date?
    public let endedAt: Date?
    public let stopReason: PixelTraceStopReason?
}
```

`PixelTraceSessionManifest` is defined in §5.1.

### 4.7 Stop reasons

```swift
/// Reason for an automatic stop triggered by a limit (used as a pure function's return value).
public enum PixelTraceLimitStopReason: String, Sendable, Codable {
    case durationLimit
    case byteLimit
}

/// The stop reason written to the manifest (also covers user action and session end).
public enum PixelTraceStopReason: String, Sendable, Codable {
    case userStopped
    case durationLimit
    case byteLimit
    case sessionEnded
    case disabled
}
```

### 4.8 Time reference

```swift
public struct PixelTraceTimestamp: Sendable, Equatable, Codable {
    public let wallClock: Date        // wall clock; serialized as ISO8601 (UTC, milliseconds)
    public let uptimeNanos: UInt64    // monotonic; derived from CLOCK_MONOTONIC_RAW
}

public enum PixelTraceClock {
    /// Returns the current time as a paired wall-clock / monotonic-clock value.
    public static func now() -> PixelTraceTimestamp

    /// The ISO8601 string format shared by all date serialization (UTC, with milliseconds).
    public static func string(from date: Date) -> String
    public static func date(from string: String) -> Date?
}
```

`PixelTraceClock`'s role is detailed in §10.

---

## 5. Data format specification

One recording session corresponds to one directory, named by the session ID (a UUID by default).

```
recordings/<session-id>/
  session.json         session manifest (rewritten in place, atomic write)
  frame_000000.jpg     frame image
  frame_000000.json    frame sidecar
  frame_000001.jpg
  frame_000001.json
  ...
  events.jsonl         tap / network / marker timeline (append-only)
```

Frame filenames use a zero-padded 6-digit sequence number, so lexicographic order matches chronological order. All JSON is emitted with `JSONEncoder`'s `.sortedKeys`, so diffs stay stable. All dates use the common ISO8601 string format (UTC, with milliseconds) defined in §10.

### 5.1 Session manifest (session.json)

Host-specific fields (camera presets, domain metadata, and the like) are kept out of the core schema entirely and pushed into the `metadata` object instead.

```swift
public struct PixelTraceSessionManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int          // schema version for this spec; 1 in the initial release
    public let pixelTraceVersion: String   // version of the package that produced this manifest
    public let sessionId: String
    public let startedAt: Date
    public let startedAtUptimeNanos: UInt64 // monotonic-clock anchor (§10)
    public let timeZoneIdentifier: String  // e.g. "Asia/Tokyo"
    public var frameCount: Int
    public var totalBytes: Int
    public var droppedFrameCount: Int      // frames dropped due to the pending-write limit
    public var skippedFrameCount: Int      // frames the host chose to thin out (§5.4)
    public var eventCount: Int             // number of lines in events.jsonl
    public var stopReason: String?         // PixelTraceStopReason.rawValue
    public var endedAt: Date?
    public let metadata: PixelTraceMetadata // host-defined (camera preset, etc.)
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `schemaVersion` | Int | required | used to detect format compatibility |
| `pixelTraceVersion` | String | required | version of the producing package |
| `sessionId` | String | required | matches the directory name |
| `startedAt` | ISO8601 string | required | wall-clock session start time |
| `startedAtUptimeNanos` | UInt64 | required | monotonic-clock anchor |
| `timeZoneIdentifier` | String | required | device time zone at recording time |
| `frameCount` | Int | required | number of frames written |
| `totalBytes` | Int | required | cumulative JPEG + JSON bytes |
| `droppedFrameCount` | Int | required | frames dropped due to backpressure |
| `skippedFrameCount` | Int | required | frames the host intentionally thinned out |
| `eventCount` | Int | required | number of timeline events |
| `stopReason` | String | optional | null if the session has not ended |
| `endedAt` | ISO8601 string | optional | null if the session has not ended |
| `metadata` | Object | required | host-defined; empty object if none |

Example:

```json
{
  "droppedFrameCount": 0,
  "endedAt": "2026-07-18T04:21:07.512Z",
  "eventCount": 34,
  "frameCount": 118,
  "metadata": {
    "cameraPreset": "hd4k",
    "appVersion": "1.4.0",
    "bufferHeight": 2160,
    "bufferWidth": 3840
  },
  "pixelTraceVersion": "0.1.0",
  "schemaVersion": 1,
  "sessionId": "6E7A...-...",
  "skippedFrameCount": 12,
  "startedAt": "2026-07-18T04:11:00.003Z",
  "startedAtUptimeNanos": 81234567890123,
  "stopReason": "sessionEnded",
  "timeZoneIdentifier": "Asia/Tokyo",
  "totalBytes": 214450176
}
```

### 5.2 Frame sidecar (frame_NNNNNN.json)

Placed next to each frame image. PixelTrace writes facts about the image itself (dimensions, pixel format, orientation, capture time); host-specific information goes into `metadata`.

```swift
public struct PixelTraceFrameSidecar: Codable, Equatable, Sendable {
    public let sequence: Int
    public let capturedAt: Date
    public let orientation: String        // CGImagePropertyOrientation's label
    public let orientationRawValue: UInt32
    public let pixelFormat: String        // FourCC string (e.g. "420f")
    public let pixelFormatRawValue: UInt32
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let jpegBytes: Int
    public let metadata: PixelTraceMetadata
}
```

`pixelFormat` is produced by a small FourCC-to-string helper (`FourCCFormatting`) that stringifies the format without needing to import CoreVideo. `orientation` is stored so that it can later be confirmed that the recorded JPEG was drawn in "the same orientation the pipeline analyzed." JPEG rendering applies `orientation` via `CIImage.oriented(_:)` before writing (§5.5).

Example:

```json
{
  "capturedAt": "2026-07-18T04:11:03.271Z",
  "jpegBytes": 1863402,
  "metadata": {
    "sceneChangeScore": 0.42,
    "confidence": 0.87,
    "captureReason": "periodicSample",
    "detectedObjectCount": 412
  },
  "orientation": "right",
  "orientationRawValue": 6,
  "pixelFormat": "420f",
  "pixelFormatRawValue": 875704422,
  "pixelHeight": 2160,
  "pixelWidth": 3840,
  "sequence": 42
}
```

### 5.3 Timeline events (events.jsonl)

Taps, network events, and markers are appended as line-delimited JSON (JSON Lines). Each line is one event, appended only, which keeps writes cheap and keeps the file naturally ordered chronologically. Every line shares a common envelope, and `type` determines the shape of `payload`.

```json
{"type":"tap","timestamp":"2026-07-18T04:11:05.880Z","payload":{"x":196.5,"y":642.0,"windowWidth":393,"windowHeight":852,"screen":"capture","phase":"down","metadata":{}}}
{"type":"network","timestamp":"2026-07-18T04:11:06.204Z","payload":{"endpoint":"/v1/search","method":"POST","statusCode":200,"latencyMs":812.4,"requestHeaders":{"authorization":"***"},"error":null,"metadata":{"service":"backend"}}}
{"type":"marker","timestamp":"2026-07-18T04:11:09.010Z","payload":{"name":"user_reported_bug","metadata":{"note":"recognition dropped out here"}}}
```

Envelope schema:

| Field | Type | Description |
| --- | --- | --- |
| `type` | String | one of `"tap"`, `"network"`, `"marker"` |
| `timestamp` | ISO8601 string | when the event occurred |
| `payload` | Object | shape depends on `type` |

`tap` payload:

| Field | Type | Description |
| --- | --- | --- |
| `x`, `y` | Double | window coordinates |
| `windowWidth`, `windowHeight` | Double | reference size for coordinate normalization |
| `screen` | String / null | host-provided screen identifier |
| `phase` | String | `"down"` / `"up"` |
| `metadata` | Object | host-defined |

`network` payload:

| Field | Type | Description |
| --- | --- | --- |
| `endpoint` | String | path (the host strips the query string before passing it in) |
| `method` | String / null | HTTP method |
| `statusCode` | Int / null | status code |
| `latencyMs` | Double / null | elapsed milliseconds to response |
| `requestHeaders`, `responseHeaders` | Object / null | after masking is applied |
| `requestBodyPreview`, `responseBodyPreview` | String / null | saved only when `captureBodies` is true, truncated to the byte limit |
| `error` | String / null | failure description |
| `metadata` | Object | host-defined |

`marker` payload:

| Field | Type | Description |
| --- | --- | --- |
| `name` | String | marker name |
| `metadata` | Object | host-defined |

### 5.4 Two kinds of missing frames

There are two distinct kinds of "frame that didn't get written," counted separately.

**droppedFrameCount**: frames dropped by PixelTrace's own backpressure. This happens when outstanding writes exceed `maxPendingWrites`, and represents a loss on the recording side.

**skippedFrameCount**: frames the host chose to thin out. When the host decides "this is a stable stretch, don't send this one" and doesn't call `submit`, it can explicitly notify PixelTrace so the count is still tracked.

Separating the two matters for judging whether a recording can be trusted: a large `droppedFrameCount` means the recording pipeline was congested, while a large `skippedFrameCount` reflects the host's own intentional thinning.

### 5.5 JPEG rendering specification

Frame images are turned into JPEG under the following rules:

- Build a `CIImage` from the input `CVPixelBuffer`, then apply `orientation` via `CIImage.oriented(_:)`.
- Only downscale proportionally when the long edge exceeds `jpegMaxLongEdge` (default 3840). The default means "1:1 up to 4K," acting as a safety valve only for oversized buffers.
- Write out via `CIContext.jpegRepresentation` at `jpegQuality` (default 0.8).
- Reuse the same `CIContext` for the whole session, using a hardware-backed renderer.

The reason downscaling doesn't happen by default is worth spelling out: this recording is also a way to judge "is text garbled because the resolution was too low," and if the recording itself downscaled, a human could no longer distinguish a genuinely low-resolution capture from one blurred by the recording step. Storage is bounded by the limits in §6 instead of by downscaling.

---

## 6. Retention policy and limits

PixelTrace has two tiers to keep storage from growing without bound, generalized here as configurable defaults from a design proven in production use.

### 6.1 Within-session limits

A single session stops automatically and finalizes as soon as either elapsed time or cumulative bytes hits its limit, whichever comes first.

- `maxDuration`: default 600 seconds.
- `maxTotalBytes`: default 500 MB.

The decision is a pure function, living in PixelTraceCore:

```swift
public enum PixelTraceLimitEvaluator {
    /// Given elapsed time and cumulative bytes, returns whichever limit was hit first.
    /// Returns nil if neither has been reached.
    public static func stopReason(
        elapsed: TimeInterval,
        totalBytes: Int,
        limits: PixelTraceLimits
    ) -> PixelTraceLimitStopReason?
}
```

When both limits are reached simultaneously, `durationLimit` is recorded preferentially (a deliberate tie-break, to keep behavior deterministic and testable).

### 6.2 Cross-session retention limit

Each time a new session starts, `recordings/` is walked in ascending order of `startedAt`, and any directories beyond the retention count are deleted in full.

- `maxRetainedSessions`: default 5.

Deletion candidate selection is a pure function in PixelTraceCore, generalized from a design proven in production use:

```swift
public struct PixelTraceSessionDirectoryEntry: Equatable, Sendable {
    public let directoryName: String
    public let startedAt: Date
    public let totalBytes: Int
}

public enum PixelTraceSessionPruning {
    /// Stacks entries in ascending order of startedAt, marking the ones beyond
    /// the count limit for deletion.
    public static func entriesToDelete(
        _ entries: [PixelTraceSessionDirectoryEntry],
        maxSessionCount: Int
    ) -> [PixelTraceSessionDirectoryEntry]
}
```

### 6.3 Combined effect of the limits

With defaults, a single session tops out at 500 MB and up to 5 sessions are retained, so total storage is bounded at 2.5 GB. This is only an automatic backstop — an explicit "delete everything" action is provided separately (§8.3).

---

## 7. DEBUG-on by default and build-configuration constraints

### 7.1 Default value

The default recording state is determined by build configuration.

```swift
extension PixelTrace {
    public static let defaultEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
```

While deployed as a DEBUG build, recording defaults to on, so there's no need to re-enable it every time. In Release builds it defaults to off, so there's no possibility of forgetting to turn it back off.

### 7.2 What `#if DEBUG` means inside a Swift Package

A SwiftPM dependency package compiles following the host app's build configuration. `swift build -c debug` and Xcode's Debug build define `DEBUG`; an archive (Release) build does not. So `#if DEBUG` inside the package tracks the host app's Debug/Release configuration.

If a host uses a non-standard setup where the package is built under a different configuration than the app itself, this correspondence can break down. Under the standard workflow (building the app in Xcode as Debug or Release), the two configurations match, and the design assumes that.

### 7.3 Two layers that disable the machinery in Release

Safety in Release builds is guaranteed by two independent layers.

The first layer is the default value: since `defaultEnabled` is false in Release, recording never starts.

The second layer is source-level disablement: the actual implementation responsible for capture and disk I/O (JPEG encoding, file writes, buffer retention) is wrapped in `#if DEBUG`, so only an empty no-op stub remains in Release. The public signatures still exist in Release, so call sites in the host don't need to be wrapped in `#if` to compile. With that in place, `submit`, `beginSession`, and the rest do nothing in Release — `isEnabled` always returns false, and calling `setEnabled(true)` does not enable anything.

Together, these two layers mean the Release binary contains none of the recording implementation, while the host's call sites compile identically regardless of configuration.

```swift
public static func submit(_ frame: PixelTraceFrame) {
    #if DEBUG
    guard isEnabled else { return }
    // actual implementation
    #else
    // no-op (recording logic is excluded from the Release binary entirely)
    #endif
}
```

---

## 8. UI component specification

PixelTraceUI provides reusable SwiftUI and UIKit components, kept minimal enough to blend into a host's own design, with slots for host-specific fields.

### 8.1 Always-on recording indicator

If recording defaults to on in DEBUG, there's a risk of operating the app without noticing it's recording. To prevent that, a small indicator is shown persistently in a screen corner.

```swift
public struct PixelTraceRecordingIndicator: View {
    public init(alignment: Alignment = .topTrailing)
}

extension View {
    /// Overlays onto a root view. Shows a red dot and "REC" only while recording.
    public func pixelTraceRecordingIndicator(
        alignment: Alignment = .topTrailing
    ) -> some View
}
```

Specification:

- Shown only while `isRecording == true`; draws nothing otherwise.
- A filled red circle with a small "REC" label, and elapsed time (optionally shown) alongside it.
- The circle pulses gently, to make the recording state easy to notice.
- Passes touches through (`allowsHitTesting(false)`), so it never interferes with camera operation underneath.
- Always hidden in Release, because `isRecording` is always false there.

### 8.2 Settings section

A generalized settings section, built around a slot for host-specific fields (`@ViewBuilder`), since PixelTrace has no concept of anything domain-specific.

```swift
public struct PixelTraceSettingsSection<HostFields: View>: View {
    public init(
        pollingInterval: Duration = .seconds(2),
        @ViewBuilder hostFields: @escaping () -> HostFields = { EmptyView() }
    )
}
```

What the section provides:

- An enable/disable toggle, calling `PixelTrace.setEnabled(_:)`.
- Explanatory copy (e.g. a note that footage of the surroundings will be captured, and to turn recording back off once done investigating; no automatic upload ever happens). The host can override this text.
- Whatever host-specific inputs are supplied via `hostFields` (for example, a document-scanning app might add fields for document type, lighting condition, or scan count).
- Status display: storage path, frame count, cumulative size, skipped-frame count, dropped-frame count, elapsed time, stop reason — polled from `PixelTrace.currentStatus()` at `pollingInterval`.
- A delete-all button (§8.3).

The status display is also exposed as a standalone view, so a host can embed it in its own layout:

```swift
public struct PixelTraceStatusView: View { public init(status: PixelTraceStatus?) }
public struct PixelTraceEnabledToggle: View { public init() }
public struct PixelTraceDeleteAllButton: View { public init(onDeleted: (() -> Void)? = nil) }
```

### 8.3 Delete-all confirmation flow

Because deleting everything is irreversible, a confirmation dialog is mandatory.

```swift
public struct PixelTraceDeleteAllButton: View {
    public init(onDeleted: (() -> Void)? = nil)
}
```

Behavior:

1. The button is styled destructively (red text), labeled to delete all recordings.
2. Tapping it presents a confirmation dialog (`confirmationDialog`).
3. The dialog states what will be deleted (all sessions, total size).
4. "Delete" is presented with a `.destructive` role and "Cancel" with a cancel role.
5. Confirming "Delete" calls `PixelTrace.deleteAllRecordings()`, then calls `onDeleted` once complete.
6. If a session is in progress, it is stopped (finalized) before the directories are removed.

---

## 9. Tap position logging implementation approach

The requirement is to leave a record of which screen and which coordinate was tapped, on the timeline. The approach chosen does not depend on the host app's view hierarchy.

### 9.1 Comparing three approaches

**Approach A: override `sendEvent(_:)` on a `UIWindow` subclass**
Replace the app's window with a subclass provided by PixelTrace, and observe every touch through `sendEvent(_:)`. It always calls `super.sendEvent(event)`, so events pass through unconsumed. The advantage is that it captures raw touch coordinates as actually delivered, regardless of whether the app is built with UIKit or SwiftUI. The disadvantage is that the host needs to swap in this window subclass, which takes an extra step under the SwiftUI app lifecycle.

**Approach B: attach a single `simultaneousGesture` at the SwiftUI root**
Add a `DragGesture(minimumDistance: 0)` via `simultaneousGesture` at the root view, recording the first position from `onChanged` as the tap start. The advantage is that it can be adopted without replacing `UIWindow`, staying entirely within SwiftUI. The disadvantage is that gesture recognition can conflict with some controls, coordinates depend on the given coordinate space, and touches inside UIKit-hosted child views are only visible as coordinates, not as detail.

**Approach C: method-swizzle `UIApplication.sendEvent`**
Not adopted. Global swizzling is exactly the category of cross-cutting side effect PixelTrace has committed to avoiding, and would contradict the reasoning in §1.4.

### 9.2 Recommendation

Approach A is recommended as primary, with Approach B offered as an alternative.

Approach A observes touches exactly as delivered and doesn't depend on UI architecture, giving it the highest fidelity. Because it only calls `super.sendEvent` and passes everything through, it doesn't change host behavior. For apps that can't replace their `UIWindow`, Approach B's SwiftUI modifier is provided as an alternative.

Neither approach walks the host's view hierarchy. What gets recorded is only window coordinates, window size, and an optional host-provided screen identifier — nothing that reaches into host-specific view concepts.

### 9.3 API

```swift
#if canImport(UIKit)
/// A window that observes sendEvent to record tap starts. Passes events through (does not consume them).
open class PixelTraceWindow: UIWindow {
    open override func sendEvent(_ event: UIEvent) {
        // Calls PixelTrace.logTap with location(in: self) for touches in the .began phase.
        super.sendEvent(event)
    }
}
#endif

extension View {
    /// An alternative for apps that cannot replace their UIWindow. Attach once at the root.
    public func pixelTraceTapLogging(
        screen: String? = nil,
        coordinateSpace: CoordinateSpace = .global
    ) -> some View
}
```

### 9.4 Coordinate normalization

Taps are recorded with both an absolute coordinate (in points) and the window size at that time. When later overlaying a tap on a recorded frame, dividing by window size gives a ratio that's comparable across devices with different screen sizes. Approach A records touch start (`.began`) by default, and can optionally record touch end (`.ended`) as well.

---

## 10. Convention for synchronizing logs and frames in time

The requirement is to be able to correlate what the host app's own logs were emitting at the moment of a bug with the timestamps on recorded frames. Each host app has its own logging system, so PixelTrace does not attempt to own logging itself. What PixelTrace provides is a clearly defined time reference, plus a thin convention and helper for getting the host's own log lines to use that same reference.

### 10.1 The reference clocks

PixelTrace treats two clocks as a pair.

**Wall clock (`Date`)**: a human-readable absolute time, used as the serialization basis. The frame sidecar's `capturedAt`, an event's `timestamp`, and the manifest's `startedAt` are all this wall clock.

**Monotonic clock (`uptimeNanos`)**: a monotonically increasing value since device boot, taken from `CLOCK_MONOTONIC_RAW`. Because the wall clock can jump due to time sync or time zone changes, this is used alongside it for strictly ordering frame or event intervals. Note that on Darwin, `CLOCK_MONOTONIC_RAW` pauses while the device is asleep, so elapsed monotonic time across a sleep/wake cycle understates real elapsed time — for a single recording session (typically well under the sleep timeout) this isn't a practical concern, but it's worth knowing if you compare monotonic deltas across a suspend. The manifest holds the monotonic-clock value at session start (`startedAtUptimeNanos`) as an anchor.

### 10.2 Unified serialization

Every date is standardized to a single ISO8601 string format (UTC, with milliseconds).

- `PixelTraceClock.string(from:)` is the sole point that produces this string.
- `JSONEncoder`'s date strategy also uses a `.custom` strategy backed by the same formatter.
- Every date in the frame sidecar, the manifest, and events.jsonl is written using this string.

PixelTrace standardizes on millisecond precision throughout — rather than the platform default ISO8601 strategy (no milliseconds) — for finer-grained ordering when correlating with logs.

### 10.3 Convention for host logs

The host prefixes each of its own log lines with a timestamp string produced by `PixelTraceClock.string(from:)`. That makes it possible to correlate a log line's timestamp with a frame sidecar's `capturedAt`, either as a string comparison or as a time comparison.

```swift
// Example host-side logging adapter
func log(_ message: String) {
    let stamp = PixelTraceClock.string(from: Date())
    myLogger.write("[\(stamp)] \(message)")
}
```

PixelTrace's responsibility ends at this convention and helper. Where logs are stored, at what level, and how they're rotated are all the host's responsibility; PixelTrace has no involvement there.

### 10.4 Where capture time comes from

Where possible, it's recommended to pass `PixelTraceFrame.capturedAt` a time derived from the sample buffer's presentation timestamp, rather than a wall-clock read taken later in the pipeline. This keeps the recorded frame's timestamp close to "the time the camera actually produced that frame," which makes correlating against logs more accurate.

---

## 11. Network visualization helper specification

Global `URLSession` swizzling is not used (§1.4). Instead, a thin logging API is provided, meant to be called explicitly from inside each of the host's own network clients.

### 11.1 How it's called

The host calls `PixelTrace.logNetworkEvent` at the point where its own networking work completes.

```swift
let start = PixelTraceClock.now()
let (data, response) = try await session.data(for: request)
let latency = elapsedMilliseconds(since: start)
PixelTrace.logNetworkEvent(
    endpoint: request.url?.path ?? "",   // pass a path without the query string
    method: request.httpMethod,
    statusCode: (response as? HTTPURLResponse)?.statusCode,
    latencyMs: latency,
    metadata: ["service": "llm"]
)
```

Because the call site lives in the host's own code, the host chooses what traffic gets recorded. Unlike a global interception approach, the recorded scope matches the host's actual intent.

### 11.2 Masking configuration

Header and body masking are exposed as configuration.

```swift
public struct PixelTraceNetworkRedaction: Sendable {
    /// Header keys whose values get masked (compared case-insensitively).
    /// Default: authorization, proxy-authorization, cookie, set-cookie,
    ///          x-api-key, api-key, apikey, x-auth-token, authentication, bearer
    public var redactedKeys: Set<String>

    /// Byte limit for stored body content. Default 2048.
    public var maxBodyPreviewBytes: Int

    /// Whether bodies are saved at all. Default false (a privacy-preserving default).
    public var captureBodies: Bool

    /// The replacement string used when masking. Default "***".
    public var redactionPlaceholder: String

    public static let `default`: PixelTraceNetworkRedaction
}
```

Rules PixelTrace applies when processing `logNetworkEvent`:

- Among `requestHeaders` and `responseHeaders`, any key matching `redactedKeys` (case-insensitive) has its value replaced with `redactionPlaceholder` before being saved.
- Bodies are only saved when `captureBodies` is true, truncated beyond `maxBodyPreviewBytes`. The default is false, so bodies are never retained unless explicitly enabled.
- URLs containing a query string are not saved. The host is expected to pass only the path as `endpoint` (PixelTrace also defensively strips anything after `?`).

### 11.3 The invariant of never writing secrets

Values such as API keys must never end up in a log. This is upheld through three measures:

- Values under known authentication header keys are masked.
- Bodies are not saved by default.
- The host is responsible for not putting secret values into free-text fields (`endpoint`, `metadata`, `error`).

PixelTrace mechanically matches header keys, truncates, and strips query strings, but it cannot detect a secret embedded in an arbitrary free-text field. That's why "don't put secrets in free-text fields" is stated explicitly as a contract the host must uphold.

---

## 12. Privacy and security policy

The invariants PixelTrace is built to uphold, listed here explicitly. These double as the pass/fail criteria for implementation tests and review.

- **No automatic upload.** Everything recorded stays entirely on-device; PixelTrace itself performs no network communication of any kind.
- **Disabled by construction in Release.** Beyond defaulting to off, the actual implementation is disabled at the source level (§7.3).
- **No secret values written.** Known authentication headers are masked, and bodies are not saved by default (§11.3).
- **Storage is bounded.** A within-session limit and a cross-session retention limit keep it capped (§6).
- **Users can notice and can erase it.** A persistent indicator shows recording is active (§8.1), and a confirmed "delete all" is provided (§8.3).
- **Stored in app-private storage.** Storage defaults to the `Caches` directory inside the app's own container, never a shared container. Files get `.complete` file protection and the backup-exclusion attribute (`isExcludedFromBackup`) set.
- **No personal information in filenames.** Filenames are sequence numbers only, independent of content.

The reason storage defaults to `Caches` is that this is inherently a temporary debug recording — something the OS is free to discard under storage pressure. For uses that need durable storage, the host can change the destination via `rootDirectory`.

---

## 13. Package structure

### 13.1 Directory layout

```
PixelTrace/
+- Package.swift
+- README.md
+- Sources/
|  +- PixelTraceCore/          Foundation only
|  |  +- Models/
|  |  |  +- PixelTraceSessionManifest.swift
|  |  |  +- PixelTraceFrameSidecar.swift
|  |  |  +- PixelTraceTimelineEvent.swift
|  |  |  +- PixelTraceJSONValue.swift
|  |  |  +- PixelTraceMetadata.swift
|  |  +- PixelTraceLimits.swift
|  |  +- PixelTraceRetention.swift
|  |  +- PixelTraceSessionPruning.swift
|  |  +- PixelTraceFrameNaming.swift
|  |  +- PixelTraceClock.swift
|  |  +- FourCCFormatting.swift
|  |  +- PixelTraceNetworkRedaction.swift
|  +- PixelTrace/              Foundation + CoreVideo + CoreImage + os
|  |  +- PixelTrace.swift             (facade)
|  |  +- PixelTraceSessionWriter.swift (actor)
|  |  +- PixelTraceJPEGRenderer.swift
|  |  +- PixelTraceFrame.swift
|  |  +- PixelTraceConfiguration.swift
|  +- PixelTraceUI/            SwiftUI + UIKit (iOS only)
|     +- PixelTraceRecordingIndicator.swift
|     +- PixelTraceSettingsSection.swift
|     +- PixelTraceStatusView.swift
|     +- PixelTraceDeleteAllButton.swift
|     +- PixelTraceTapLogging.swift
+- Tests/
   +- PixelTraceCoreTests/     pure logic tests, run without a simulator
   +- PixelTraceTests/         capture and write tests
```

### 13.2 Package.swift outline

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixelTrace",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)   // so PixelTraceCore can be tested on macOS
    ],
    products: [
        .library(name: "PixelTraceCore", targets: ["PixelTraceCore"]),
        .library(name: "PixelTrace", targets: ["PixelTrace"]),
        .library(name: "PixelTraceUI", targets: ["PixelTraceUI"]),
    ],
    targets: [
        .target(name: "PixelTraceCore"),
        .target(name: "PixelTrace", dependencies: ["PixelTraceCore"]),
        .target(name: "PixelTraceUI", dependencies: ["PixelTrace", "PixelTraceCore"]),
        .testTarget(name: "PixelTraceCoreTests", dependencies: ["PixelTraceCore"]),
        .testTarget(name: "PixelTraceTests", dependencies: ["PixelTrace"]),
    ]
)
```

PixelTraceUI depends on UIKit and SwiftUI, so it's for iOS. UIKit-dependent parts are wrapped in `#if canImport(UIKit)` so a macOS build (of PixelTraceCore) doesn't break. There are no external dependencies anywhere in the package.

### 13.3 Avoiding name collisions

To stay addable independently across multiple projects, public symbol namespacing is enforced throughout.

- Every public type, protocol, and enum is prefixed with `PixelTrace` (`PixelTraceFrame`, `PixelTraceSessionManifest`, etc.).
- Public free functions are consolidated as static methods on the `enum PixelTrace` facade (no public top-level functions).
- SwiftUI `View` extension methods are prefixed with `pixelTrace` (`pixelTraceRecordingIndicator`, `pixelTraceTapLogging`).
- Module names are also `PixelTrace`-prefixed, so they don't collide with a host's own module names.

---

## 14. Implementation roadmap

Implementation proceeds in phases. Each phase builds on the previous one and is independently testable.

**Phase 0: PixelTraceCore**
Implement the Codable models, `PixelTraceLimits` / `PixelTraceLimitEvaluator`, `PixelTraceRetention` / `PixelTraceSessionPruning`, `PixelTraceFrameNaming`, `PixelTraceClock`, `PixelTraceJSONValue` / `PixelTraceMetadata`, and `FourCCFormatting`. Foundation-only, with simulator-free tests throughout.

**Phase 1: Capture and disk writing**
Implement `PixelTraceSessionWriter` (actor), the `PixelTrace` facade, and `PixelTraceJPEGRenderer`. Covers backpressure, the two kinds of missing-frame counting, within-session limits, retention limits, and atomic manifest writes, aiming for functional parity with a proven prior implementation.

**Phase 2: UI components**
Implement the recording indicator, settings section, status display, and the delete-all button (with its confirmation flow).

**Phase 3: Tap position logging and timeline**
Implement `PixelTraceWindow`, `.pixelTraceTapLogging()`, and appending to events.jsonl.

**Phase 4: Network visualization**
Implement `logNetworkEvent` and the masking configuration.

**Phase 5: Time synchronization convention and helpers**
Finalize `PixelTraceClock`'s unified serialization and usage examples for hosts.

**Phase 6: Integration into a production host app**
Adopt PixelTrace in a real host app, replacing or wrapping any prior bespoke recording implementation, and validate the design against real-world use.

**Phase 7: Second host app integration and documentation polish**
Follow the from-scratch integration steps (see the README's Quick Start) in a second host app, and fold anything that was unclear back into this documentation.

## 15. Extensibility

PixelTrace is primarily a personal debugging instrument, and the most valuable use cases are the ones a general-purpose tool cannot anticipate. To let a host adapt the recorder to those cases without forking it, three extension points are exposed on `PixelTraceConfiguration`. All three are additive and optional: leaving them unset preserves the default behavior described in the preceding sections. By design, the recorder does not attempt to guard against misuse of these hooks — the correctness and privacy of a custom hook are the host's responsibility. The guiding constraint is the one from §1: enable debugging that ordinary tools cannot, and add no abstraction that does not serve that goal.

### 15.1 Frame encoding strategy (`PixelTraceFrameEncoding`)

By default each frame is encoded as JPEG by `PixelTraceJPEGRenderer`, using the configuration's `jpegQuality` and `jpegMaxLongEdge`, and written as `frame_NNNNNN.jpg`. A host can substitute its own encoder by setting `configuration.frameEncoder` to any type conforming to:

```swift
public protocol PixelTraceFrameEncoding: Sendable {
    var fileExtension: String { get }
    func encode(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data?
}
```

The writer uses the encoder's `fileExtension` for the frame file's suffix and its `encode(_:orientation:)` output as the file's bytes; the sidecar JSON and all other bookkeeping are unchanged. This lets a host record lossless PNG, burn a debug overlay into the frame, or apply a domain-specific codec. When `frameEncoder` is `nil` (the default), the built-in JPEG path is used verbatim, including its shared `CIContext`. `PixelTraceJPEGFrameEncoder` is provided as the reified default and as a template for wrapping the built-in renderer.

### 15.2 Custom network redaction (`customNetworkRedactor`)

By default `logNetworkEvent` applies field-level redaction (§11): known auth headers are masked, query strings are stripped, and bodies are dropped unless `captureBodies` is enabled. A host that needs different rules — masking a bespoke token header, hashing an identifier, or keeping a body it knows to be safe — can set:

```swift
public var customNetworkRedactor: (@Sendable (PixelTraceNetworkEvent) -> PixelTraceNetworkEvent)?
```

When set, this closure completely replaces the built-in redaction: PixelTrace passes it the event, records the returned event's fields verbatim, and performs no header masking, query stripping, or body gating of its own. Because the closure decides exactly what is written, the host owns the privacy guarantee for network events; the default (`nil`) keeps the safe built-in behavior. This hook lives on `PixelTraceConfiguration` rather than on `PixelTraceNetworkRedaction` because the event type belongs to the capture layer, while the redaction value type is part of the dependency-free core (§13) and is `Equatable` — keeping the closure out of the core preserves both the module layering and that value semantics.

### 15.3 Lifecycle observation (`PixelTraceObserving`)

To let a host react to recording as it happens — stream frames to a live preview, mirror events into its own logging, or drive custom instrumentation — a host can set `configuration.observer` to any type conforming to:

```swift
public protocol PixelTraceObserving: Sendable {
    func pixelTraceDidBeginSession(_ session: PixelTraceObservedSession)
    func pixelTraceDidWriteFrame(_ frame: PixelTraceObservedFrame)
    func pixelTraceDidEndSession(_ summary: PixelTraceObservedSessionEnd)
}
```

The observer is invoked from inside the writer actor at three points: after a session's initial manifest is written, after each frame and its sidecar are written (the callback carries the encoded frame `Data`, its on-disk URL, the sequence number, and the capture timestamp), and once when the session is finalized (with the stop reason and final counts). Crucially, these calls are made from the writer's serialized, off-capture-thread context, never from `submit(_:)` — so an observer, however slow, cannot block the host's capture thread. A slow observer can only slow the writer's own drain, which is already governed by the backpressure contract of §3.2 (excess frames are dropped and counted, never blocked on).
