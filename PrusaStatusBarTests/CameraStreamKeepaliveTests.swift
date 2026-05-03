import AppKit
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Camera tile opens dedicated zoomed window
///   - Scenario "Last popup close stops go2rtc"
///   - Scenario "Popover close with popup open does not stop go2rtc"
///   - Scenario "Popup persists after popover dismissal"
@MainActor
struct CameraStreamKeepaliveTests {
    @Test
    func popoverCloseWithNoPopupsCallsStop() {
        let stopper = StopSpy()
        let keepalive = CameraStreamKeepalive(stopGoRTC: stopper.record)

        keepalive.popoverDidShow()
        keepalive.popoverDidClose()

        #expect(stopper.calls == 1)
    }

    @Test
    func popoverCloseWithPopupOpenSkipsStop() {
        let stopper = StopSpy()
        let keepalive = CameraStreamKeepalive(stopGoRTC: stopper.record)

        keepalive.popoverDidShow()
        keepalive.register(.buddy)
        keepalive.popoverDidClose()

        #expect(stopper.calls == 0)
        #expect(keepalive.popupCount == 1)
    }

    @Test
    func lastPopupCloseAfterPopoverClosedStopsGoRTC() {
        let stopper = StopSpy()
        let keepalive = CameraStreamKeepalive(stopGoRTC: stopper.record)

        keepalive.popoverDidShow()
        keepalive.register(.buddy)
        keepalive.register(.generic)
        keepalive.popoverDidClose()
        #expect(stopper.calls == 0)

        keepalive.deregister(.buddy)
        // Still one popup open, do not stop yet.
        #expect(stopper.calls == 0)

        keepalive.deregister(.generic)
        // Last popup closed, no popover, now we stop.
        #expect(stopper.calls == 1)
    }

    @Test
    func popupCloseWhilePopoverVisibleDoesNotStop() {
        let stopper = StopSpy()
        let keepalive = CameraStreamKeepalive(stopGoRTC: stopper.record)

        keepalive.popoverDidShow()
        keepalive.register(.buddy)
        keepalive.deregister(.buddy)

        #expect(stopper.calls == 0)
    }

    @Test
    func registerIsIdempotent() {
        let stopper = StopSpy()
        let keepalive = CameraStreamKeepalive(stopGoRTC: stopper.record)

        keepalive.register(.buddy)
        keepalive.register(.buddy)
        #expect(keepalive.popupCount == 1)

        keepalive.deregister(.buddy)
        #expect(keepalive.popupCount == 0)
    }
}

@MainActor
private final class StopSpy {
    var calls: Int = 0
    func record() {
        calls += 1
    }
}
