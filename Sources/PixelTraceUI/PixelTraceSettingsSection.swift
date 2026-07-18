#if canImport(SwiftUI)
import SwiftUI
import PixelTrace

/// A drop-in debug settings section: the enable toggle, an explanatory note, a host-supplied
/// fields slot, a live status readout, and the delete-all button. Intended to be placed inside
/// a `Form`/`Section` by the host (spec §8.2).
public struct PixelTraceSettingsSection<HostFields: View>: View {
    private let pollingInterval: Duration
    private let toggleTitle: String
    private let note: String
    private let hostFields: () -> HostFields

    @State private var status: PixelTraceStatus?

    public init(
        pollingInterval: Duration = .seconds(2),
        toggleTitle: String = "Record camera frames",
        note: String = "Camera frames are recorded on-device for debugging. Your surroundings may be captured, so turn this off when you're done investigating. Nothing is ever uploaded.",
        @ViewBuilder hostFields: @escaping () -> HostFields = { EmptyView() }
    ) {
        self.pollingInterval = pollingInterval
        self.toggleTitle = toggleTitle
        self.note = note
        self.hostFields = hostFields
    }

    public var body: some View {
        Group {
            PixelTraceEnabledToggle(title: toggleTitle)

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)

            hostFields()

            PixelTraceStatusView(status: status)

            PixelTraceDeleteAllButton { status = nil }
        }
        .task {
            while !Task.isCancelled {
                status = await PixelTrace.currentStatus()
                try? await Task.sleep(for: pollingInterval)
            }
        }
    }
}
#endif
