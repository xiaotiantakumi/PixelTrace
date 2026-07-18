#if canImport(SwiftUI)
import SwiftUI
import XCTest
import PixelTraceUI

@MainActor
final class PixelTraceTapLoggingSmokeTests: XCTestCase {
    func testTapLoggingModifierApplies() {
        _ = Color.clear.pixelTraceTapLogging()
        _ = Color.clear.pixelTraceTapLogging(screen: "root", coordinateSpace: .local)
    }
}
#endif
