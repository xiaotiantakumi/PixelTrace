#if canImport(UIKit)
import UIKit
import PixelTrace

/// A `UIWindow` subclass that observes touches and logs their start location to the timeline,
/// passing every event through untouched (spec §9.2, case A). Because `super.sendEvent(_:)` is
/// always called, this never consumes or alters events. Host apps install this in place of the
/// default window.
open class PixelTraceWindow: UIWindow {
    /// Optional screen identifier attached to logged taps.
    public var pixelTraceScreenName: String?

    /// When true, touch-ended events are also logged. Defaults to false (touch-began only).
    public var pixelTraceLogsTouchEnded: Bool = false

    open override func sendEvent(_ event: UIEvent) {
        logTouches(in: event)
        super.sendEvent(event)
    }

    private func logTouches(in event: UIEvent) {
        guard let touches = event.allTouches else { return }
        let windowSize = bounds.size
        let screen = pixelTraceScreenName
        for touch in touches {
            let phase: PixelTraceTapEvent.Phase
            switch touch.phase {
            case .began:
                phase = .down
            case .ended where pixelTraceLogsTouchEnded:
                phase = .up
            default:
                continue
            }
            PixelTrace.logTap(PixelTraceTapEvent(
                location: touch.location(in: self),
                windowSize: windowSize,
                screen: screen,
                phase: phase
            ))
        }
    }
}
#endif
