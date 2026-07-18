#if canImport(SwiftUI)
import SwiftUI
import PixelTrace
import PixelTraceCore

/// Displays a recording status snapshot. Host apps can embed this in their own layout.
public struct PixelTraceStatusView: View {
    private let status: PixelTraceStatus?

    public init(status: PixelTraceStatus?) {
        self.status = status
    }

    public var body: some View {
        if let status {
            if let path = status.directoryPath {
                LabeledContent("Location") {
                    Text(path)
                        .font(.caption2)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
            LabeledContent("Frames") { Text("\(status.frameCount)") }
            LabeledContent("Total size") { Text(Self.megabytes(status.totalBytes)) }
            LabeledContent("Skipped (host)") { Text("\(status.skippedFrameCount)") }
            LabeledContent("Dropped (backpressure)") { Text("\(status.droppedFrameCount)") }
            if let startedAt = status.startedAt {
                LabeledContent("Elapsed") {
                    Text(Self.elapsed(from: startedAt, to: status.endedAt))
                }
            }
            if let stopReason = status.stopReason {
                LabeledContent("Stopped") {
                    Text(Self.stopReasonLabel(stopReason)).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No active recording session")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
    }

    private static func elapsed(from start: Date, to end: Date?) -> String {
        let seconds = max(0, Int((end ?? Date()).timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func stopReasonLabel(_ reason: PixelTraceStopReason) -> String {
        switch reason {
        case .userStopped: return "Stopped by user"
        case .durationLimit: return "Duration limit reached"
        case .byteLimit: return "Size limit reached"
        case .sessionEnded: return "Session ended"
        case .disabled: return "Recording disabled"
        }
    }
}
#endif
