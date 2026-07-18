#if canImport(SwiftUI)
import SwiftUI
import PixelTrace

/// A SwiftUI alternative to `PixelTraceWindow` for apps that cannot swap their window
/// (spec §9.2, case B). Add it once at the root. A zero-distance drag gesture is observed
/// simultaneously (it never consumes the touch), and the first movement of each gesture is
/// recorded as a tap-down.
extension View {
    public func pixelTraceTapLogging(
        screen: String? = nil,
        coordinateSpace: CoordinateSpace = .global
    ) -> some View {
        modifier(PixelTraceTapLoggingModifier(screen: screen, coordinateSpace: coordinateSpace))
    }
}

private struct PixelTraceTapLoggingModifier: ViewModifier {
    let screen: String?
    let coordinateSpace: CoordinateSpace

    @State private var containerSize: CGSize = .zero
    @State private var isTrackingTouch = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerSize = proxy.size }
                        .onChange(of: proxy.size) { newSize in containerSize = newSize }
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: coordinateSpace)
                    .onChanged { value in
                        guard !isTrackingTouch else { return }
                        isTrackingTouch = true
                        PixelTrace.logTap(PixelTraceTapEvent(
                            location: value.startLocation,
                            windowSize: containerSize,
                            screen: screen,
                            phase: .down
                        ))
                    }
                    .onEnded { _ in
                        isTrackingTouch = false
                    }
            )
    }
}
#endif
