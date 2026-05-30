import AppKit
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Camera tile opens dedicated zoomed window
///   - Scenario "Click on Buddy tile opens popup"
///   - Scenario "Second click reuses existing window"
///   - Scenario "Both tiles open simultaneously"
///   - Scenario "Source change between opens refreshes content"
@MainActor
struct CameraQuickLookWindowControllerTests {
    @Test
    func presentRegistersWithKeepalive() {
        let keepalive = CameraStreamKeepalive(stopPlayers: {})
        let controller = CameraQuickLookWindowController(
            kind: .buddy,
            keepalive: keepalive,
            activate: { _ in }
        )

        controller.present(
            source: .prototype(label: "Buddy", systemImage: "video"),
            title: "Buddy Camera"
        )

        #expect(keepalive.popupCount == 1)

        // Tear down so subsequent tests do not leak a window.
        controller.windowWillClose(notification(for: controller))
        #expect(keepalive.popupCount == 0)
    }

    @Test
    func secondPresentDoesNotRegisterAgainAndUpdatesSource() {
        let keepalive = CameraStreamKeepalive(stopPlayers: {})
        let controller = CameraQuickLookWindowController(
            kind: .buddy,
            keepalive: keepalive,
            activate: { _ in }
        )

        let firstSource = CameraQuickLookSource.prototype(label: "Buddy", systemImage: "video")
        let secondSource = CameraQuickLookSource.prototype(label: "Buddy 2", systemImage: "video")

        controller.present(source: firstSource, title: "Buddy Camera")
        let firstWindow = controller.window
        controller.present(source: secondSource, title: "Buddy Camera")
        let secondWindow = controller.window

        #expect(keepalive.popupCount == 1)
        #expect(firstWindow === secondWindow)
        #expect(controller.currentSource == secondSource)

        controller.windowWillClose(notification(for: controller))
    }

    @Test
    func independentControllersTrackSeparateWindows() {
        let keepalive = CameraStreamKeepalive(stopPlayers: {})
        let buddy = CameraQuickLookWindowController(
            kind: .buddy,
            keepalive: keepalive,
            activate: { _ in }
        )
        let generic = CameraQuickLookWindowController(
            kind: .generic,
            keepalive: keepalive,
            activate: { _ in }
        )

        buddy.present(
            source: .prototype(label: "Buddy", systemImage: "video"),
            title: "Buddy Camera"
        )
        generic.present(
            source: .prototype(label: "Generic", systemImage: "video.badge.plus"),
            title: "Generic Camera"
        )

        #expect(keepalive.popupCount == 2)

        buddy.windowWillClose(notification(for: buddy))
        #expect(keepalive.popupCount == 1)

        generic.windowWillClose(notification(for: generic))
        #expect(keepalive.popupCount == 0)
    }

    /// Build a synthetic close notification carrying the controller's
    /// current window. Mirrors the real AppKit signature without spinning
    /// the runloop.
    private func notification(for controller: CameraQuickLookWindowController) -> Notification {
        Notification(name: NSWindow.willCloseNotification, object: controller.window)
    }
}
