#if canImport(SwiftUI)
import SwiftUI
import XCTest
import PixelTraceUI

/// Compile/construction smoke tests: verify the public UI API is usable from a client module
/// (public inits, generic defaults, and the View extension). SwiftUI rendering is not exercised.
@MainActor
final class PixelTraceUISmokeTests: XCTestCase {
    func testPublicViewsConstruct() {
        _ = PixelTraceRecordingIndicator()
        _ = PixelTraceRecordingIndicator(alignment: .bottomLeading, showsElapsed: false)
        _ = PixelTraceEnabledToggle()
        _ = PixelTraceEnabledToggle(title: "Record")
        _ = PixelTraceStatusView(status: nil)
        _ = PixelTraceDeleteAllButton()
        _ = PixelTraceDeleteAllButton(title: "Delete") {}
    }

    func testSettingsSectionConstructsWithAndWithoutHostFields() {
        _ = PixelTraceSettingsSection()
        _ = PixelTraceSettingsSection {
            Text("host field")
        }
    }

    func testRecordingIndicatorModifierApplies() {
        _ = Color.clear.pixelTraceRecordingIndicator()
        _ = Color.clear.pixelTraceRecordingIndicator(alignment: .top)
    }
}
#endif
