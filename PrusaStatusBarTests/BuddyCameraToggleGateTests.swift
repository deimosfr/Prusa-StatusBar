@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` (always-show-buddy-camera-section delta) Requirement:
///   Printer tab edits Buddy Camera host. The Buddy Camera toggle is
///   non-interactive whenever the live PrusaLink URL field is empty.
struct BuddyCameraToggleGateTests {
    @Test
    func toggleDisabledWhenURLEmpty() {
        #expect(!BuddyCameraSection.isToggleEnabled(forURLField: ""))
    }

    @Test
    func toggleDisabledWhenURLOnlyWhitespace() {
        #expect(!BuddyCameraSection.isToggleEnabled(forURLField: "   "))
        #expect(!BuddyCameraSection.isToggleEnabled(forURLField: "\t\n"))
    }

    @Test
    func toggleEnabledForPlainHost() {
        #expect(BuddyCameraSection.isToggleEnabled(forURLField: "192.168.1.10"))
    }

    @Test
    func toggleEnabledForFullURL() {
        #expect(BuddyCameraSection.isToggleEnabled(forURLField: "http://prusa.local"))
    }

    @Test
    func toggleEnabledIgnoresSurroundingWhitespace() {
        #expect(BuddyCameraSection.isToggleEnabled(forURLField: "  prusa.local  "))
    }
}
