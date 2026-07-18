#if canImport(SwiftUI)
import SwiftUI
import PixelTrace

/// A toggle bound to `PixelTrace.setEnabled(_:)`.
public struct PixelTraceEnabledToggle: View {
    private let title: String
    @State private var isEnabled = PixelTrace.isEnabled

    public init(title: String = "Record camera frames") {
        self.title = title
    }

    public var body: some View {
        Toggle(title, isOn: $isEnabled)
            .onChange(of: isEnabled) { newValue in
                PixelTrace.setEnabled(newValue)
            }
            .onAppear { isEnabled = PixelTrace.isEnabled }
    }
}
#endif
