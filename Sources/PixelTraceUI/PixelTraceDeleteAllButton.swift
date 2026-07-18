#if canImport(SwiftUI)
import SwiftUI
import PixelTrace

/// A destructive "delete all recordings" button with a required confirmation dialog (spec §8.3).
public struct PixelTraceDeleteAllButton: View {
    private let title: String
    private let onDeleted: (() -> Void)?

    @State private var isConfirming = false
    @State private var isDeleting = false

    public init(title: String = "Delete all recordings", onDeleted: (() -> Void)? = nil) {
        self.title = title
        self.onDeleted = onDeleted
    }

    public var body: some View {
        Button(role: .destructive) {
            isConfirming = true
        } label: {
            Text(title)
        }
        .disabled(isDeleting)
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    // Any in-progress session is finalized before the directory is removed.
                    try? await PixelTrace.deleteAllRecordings()
                    isDeleting = false
                    onDeleted?()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every recorded session on this device. This cannot be undone.")
        }
    }
}
#endif
