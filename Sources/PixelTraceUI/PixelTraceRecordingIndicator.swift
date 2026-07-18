#if canImport(SwiftUI)
import SwiftUI
import PixelTrace

/// An always-on recording indicator. Shows a blinking red dot and "REC" while a session is
/// recording, and nothing otherwise. Tap-transparent so it never blocks the camera UI beneath
/// it. In Release the status is always non-recording, so it stays hidden (spec §8.1).
public struct PixelTraceRecordingIndicator: View {
    private let alignment: Alignment
    private let showsElapsed: Bool

    @State private var isRecording = false
    @State private var startedAt: Date?
    @State private var now = Date()
    @State private var isBlinking = false

    public init(alignment: Alignment = .topTrailing, showsElapsed: Bool = true) {
        self.alignment = alignment
        self.showsElapsed = showsElapsed
    }

    public var body: some View {
        badge
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .allowsHitTesting(false)
            .task {
                isBlinking = true
                while !Task.isCancelled {
                    let status = await PixelTrace.currentStatus()
                    isRecording = status?.isRecording ?? false
                    startedAt = status?.startedAt
                    now = Date()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }

    @ViewBuilder
    private var badge: some View {
        if isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(isBlinking ? 0.35 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isBlinking)
                Text("REC")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                if showsElapsed, let startedAt {
                    Text(elapsedString(from: startedAt))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(8)
        }
    }

    private func elapsedString(from start: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension View {
    /// Overlays a recording indicator on the root view. Only visible while recording.
    public func pixelTraceRecordingIndicator(alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) {
            PixelTraceRecordingIndicator(alignment: alignment)
        }
    }
}
#endif
