import AppKit
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Streaming pauses while popover is closed
///   - Scenario "Closing the popover stops the pipeline"
///   - Scenario "Reopening the popover resumes the pipeline"
@MainActor
struct PopoverLifecycleTests {
    @Test
    func popoverVisibleDefaultsToFalse() {
        let model = AppModel()
        #expect(model.popoverVisible == false)
    }

    @Test
    func popoverDidShowFlipsVisibleAndBumpsToken() {
        let model = AppModel()
        let delegate = MenuBarPopoverDelegate(model: model, onClose: {})
        let initialToken = model.popoverShowToken

        delegate.handlePopoverDidShow()

        #expect(model.popoverVisible == true)
        #expect(model.popoverShowToken == initialToken &+ 1)
    }

    @Test
    func popoverDidCloseFlipsVisibleAndCallsStopper() {
        let model = AppModel()
        model.popoverVisible = true
        let stopper = StopperSpy()
        let delegate = MenuBarPopoverDelegate(model: model, onClose: stopper.record)

        delegate.handlePopoverDidClose()

        #expect(model.popoverVisible == false)
        #expect(stopper.calls == 1)
    }

    @Test
    func reopeningResetsVisibilityForFreshMount() {
        let model = AppModel()
        let stopper = StopperSpy()
        let delegate = MenuBarPopoverDelegate(model: model, onClose: stopper.record)

        delegate.handlePopoverDidShow()
        delegate.handlePopoverDidClose()
        delegate.handlePopoverDidShow()

        #expect(model.popoverVisible == true)
        #expect(stopper.calls == 1)
    }

    /// Spec: "Popover close with popup open does not stop the player".
    /// When the keepalive sees an open popup, its close hook MUST NOT
    /// invoke the stop closure.
    @Test
    func keepaliveDefersStopWhilePopupOpen() {
        let stopper = StopperSpy()
        let keepalive = CameraStreamKeepalive(stopPlayers: stopper.record)
        let model = AppModel()
        let delegate = MenuBarPopoverDelegate(
            model: model,
            onShow: { keepalive.popoverDidShow() },
            onClose: { keepalive.popoverDidClose() }
        )

        delegate.handlePopoverDidShow()
        keepalive.register(.buddy)
        delegate.handlePopoverDidClose()

        #expect(stopper.calls == 0)

        keepalive.deregister(.buddy)
        #expect(stopper.calls == 1)
    }
}

@MainActor
private final class StopperSpy {
    var calls: Int = 0

    func record() {
        calls += 1
    }
}
