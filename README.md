# PixelTrace

**On-device, real-footage debug recording for camera-first iOS apps.**

PixelTrace is a Swift Package that captures the exact `CVPixelBuffer` frames your video pipeline is already processing — from `AVCaptureVideoDataOutput` or any other source — and writes them to disk on-device as JPEG frames with sidecar JSON, alongside a session manifest and a timeline of taps, network events, and custom markers. It is built for apps where the camera preview fills most of the screen: OCR readers, document scanners, real-time image recognition, translation cameras, and similar.

## Why

Apps that process camera video continuously — reading text, detecting objects, scanning documents — have a recurring debugging problem: most bugs depend on *what the camera actually saw*. Blurry frames, a detector losing its lock between frames, exposure-dependent recognition failures — these can't be diagnosed after the fact unless you can go back and look at the actual frame the pipeline processed.

Standard session-replay tooling doesn't help here. Screen-recording approaches based on view-hierarchy snapshots (e.g. `UIWindow.drawHierarchy(in:afterScreenUpdates:)`) cannot capture hardware-composited layers like `AVCaptureVideoPreviewLayer` — the camera preview renders as black or blank. For an app whose main screen *is* the camera preview, that's exactly the part you need to see. See [`docs/DESIGN.md`](docs/DESIGN.md) for the full explanation of why this is a structural limitation, not an implementation bug.

PixelTrace takes a different approach: it records the same pixel buffer your pipeline consumes, directly, with no dependency on UI compositing.

### Non-goals

- **Not a general-purpose screen recorder.** It does not capture view hierarchies or arbitrary UI.
- **Not a logging framework.** PixelTrace doesn't own your log output; it provides a shared time reference so your existing logs and recorded frames can be correlated (see Design doc §10).
- **No automatic network interception.** No global `URLSession` swizzling. You call an explicit logging function from your own network code when you want an event recorded.
- **No automatic upload, ever.** Everything stays on-device.
- **Not for Release builds.** This is a development-time debugging instrument, not an analytics or crash-reporting tool.

## Features

- **Raw pixel buffer recording** — records the actual `CVPixelBuffer` your pipeline processes, encoded as JPEG at up to 4K with a configurable quality, alongside a JSON sidecar describing dimensions, pixel format, orientation, and host-defined metadata.
- **Structured timeline** — tap positions, network events (with header redaction and opt-in, size-capped body capture), and arbitrary markers are appended to a single JSON Lines timeline (`events.jsonl`), correlated with recorded frames by timestamp.
- **DEBUG-on by default, Release-off by construction** — recording defaults to on in DEBUG builds and off in Release builds; in Release, the recording implementation itself compiles down to a no-op, so the capture and disk I/O code isn't present in the shipped binary.
- **Bounded storage** — a per-session cap (duration and total bytes) and a cross-session retention cap (max number of retained sessions) keep on-device storage from growing unbounded, on top of a one-tap "delete all" control.
- **Zero external dependencies** — built entirely on Apple's standard frameworks (Foundation, CoreVideo, CoreImage, os), so it adds no third-party dependency footprint to a host app.
- **Non-blocking by design** — `submit(_:)` returns immediately from the capture thread; encoding and disk I/O happen off to the side, with backpressure that drops frames (and counts the drops) rather than stalling your pipeline.
- **Always-visible recording indicator** — a small, tap-through "REC" indicator so recording is never silently happening in the background.
- **Customizable by design** — swap the frame encoder (e.g. lossless PNG or overlay-burned frames), replace network redaction with your own rules, or observe the session/frame lifecycle to stream frames into your own live view. See [`docs/DESIGN.md`](docs/DESIGN.md) §15.

## Requirements

- iOS 16.0+
- Swift 5.9+ / Swift tools version 5.9
- macOS 13+ (optional — only needed if you want to build and test the dependency-free `PixelTraceCore` logic layer — limits, retention, pruning, naming, clock — without an iOS simulator)

## Installation

### Swift Package Manager

Add PixelTrace as a package dependency via Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/xiaotiantakumi/PixelTrace.git
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/xiaotiantakumi/PixelTrace.git", from: "0.1.0")
]
```

Then add the modules you need to your target. Most apps want `PixelTrace` (capture + disk I/O) and `PixelTraceUI` (SwiftUI/UIKit components):

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "PixelTrace", package: "PixelTrace"),
        .product(name: "PixelTraceUI", package: "PixelTrace"),
    ]
)
```

If you only need the dependency-free logic layer (e.g. to unit test retention/pruning behavior without a simulator), depend on `PixelTraceCore` alone.

## Quick start

The core integration point is: wherever your app already gets a `CVPixelBuffer` off the camera and hands it to your processing pipeline, hand a copy to PixelTrace too.

```swift
import PixelTrace
import PixelTraceUI

// 1. Configure once at launch (optional — defaults are reasonable).
PixelTrace.configure(.default)

// 2. Start a session when recording should begin (e.g. when the camera starts).
await PixelTrace.beginSession(PixelTraceSessionContext(
    metadata: ["cameraPreset": "hd4k"]
))

// 3. In your capture callback, alongside your existing pipeline call:
func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    // Your existing pipeline call — unchanged.
    myPipeline.process(pixelBuffer)

    // New: hand the same buffer to PixelTrace.
    PixelTrace.submit(PixelTraceFrame(
        pixelBuffer: pixelBuffer,
        orientation: .right,
        metadata: ["frameKind": "periodicSample"]
    ))
}

// 4. End the session when recording should stop.
await PixelTrace.endSession()
```

Layer in the rest as needed:

```swift
// Show a "REC" indicator so recording is never silent.
YourRootView()
    .pixelTraceRecordingIndicator()
    .pixelTraceTapLogging()   // logs tap position into the timeline

// Surface a settings section with a toggle, status, and a confirmed "delete all".
PixelTraceSettingsSection()

// Log a network call from your own client code, at the completion point.
PixelTrace.logNetworkEvent(
    endpoint: request.url?.path ?? "",
    method: request.httpMethod,
    statusCode: (response as? HTTPURLResponse)?.statusCode,
    latencyMs: latency
)

// Stamp your own log lines with the same clock PixelTrace uses,
// so log lines and recorded frames can be correlated by timestamp.
myLogger.write("[\(PixelTraceClock.string(from: Date()))] \(message)")
```

That's the whole integration surface. See [`docs/DESIGN.md`](docs/DESIGN.md) for the complete API reference, data formats, and design rationale.

## Module layout

PixelTrace is split into three layers so a host app can depend on only what it needs:

| Module | Depends on | Contains |
| --- | --- | --- |
| **PixelTraceCore** | Foundation only | Codable models, limit/retention evaluation, session pruning, frame naming, clock — all pure logic, testable without a simulator |
| **PixelTrace** | PixelTraceCore + CoreVideo/CoreImage/os | Pixel buffer capture, JPEG encoding, disk I/O, the public `PixelTrace` facade |
| **PixelTraceUI** | PixelTrace + SwiftUI/UIKit | Recording indicator, settings section, tap-logging window/modifier, delete-all button |

An app that builds its own settings UI can depend on `PixelTrace` alone; a process that only needs to reason about retention/pruning logic can depend on `PixelTraceCore` alone.

## Privacy and security

- **No automatic upload.** Everything recorded stays on-device; PixelTrace performs no network communication of its own.
- **Disabled by construction in Release.** Beyond defaulting to off, the actual capture/encode/write implementation is compiled out in Release builds (`#if DEBUG`), so it isn't present in the shipped binary at all.
- **No secrets in logs.** Known authentication header keys (`authorization`, `cookie`, `x-api-key`, etc.) are redacted automatically, and request/response bodies are not captured unless explicitly opted in.
- **Bounded storage.** A per-session cap and a cross-session retention cap keep on-device usage bounded, with a confirmed "delete all" for immediate cleanup.
- **Discoverable and erasable.** A persistent on-screen indicator shows when recording is active; nothing records silently.
- **App-sandboxed storage.** Recordings default to the app's own `Caches` directory (not a shared container), with complete file protection and backup exclusion applied.
- **No identifying information in filenames.** Frame files are named by sequence number only.

See [`docs/DESIGN.md`](docs/DESIGN.md) §12 for the full policy.

## License

MIT — see [LICENSE](LICENSE).

## Background

This package generalizes a recording foundation that was first built and proven inside a different, private iOS app that keeps a camera feed on-screen continuously. PixelTrace re-packages that foundation as a standalone, host-agnostic library, with the host-specific concepts (what the camera was looking at, why a frame was interesting) factored out into a generic metadata slot that any host app can fill in.
