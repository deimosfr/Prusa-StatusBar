import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Menu-bar printing icon plays bounded burst
///   animation. Asserts the `PollingCoordinator` side: every non-printing ->
///   printing transition (including `.paused`) bumps
///   `AppModel.printingBurstToken`; staying-in-printing or non-printing
///   transitions do not. The first observation (no prior state) is
///   intentionally suppressed so the launch path stays controller-driven.
@MainActor
struct PollingCoordinatorBurstTokenTests {
    private func makeCoordinator() -> (PollingCoordinator, AppModel) {
        let model = AppModel()
        let client = StubPrusaLinkClient(phase: .idle)
        let notifier = StubNotificationService()
        let coordinator = PollingCoordinator(model: model, client: client, notifier: notifier)
        return (coordinator, model)
    }

    @Test
    func idleToPrintingBumpsToken() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .idle, current: .printing)
        #expect(model.printingBurstToken == before &+ 1)
    }

    @Test
    func pausedToPrintingBumpsToken() {
        // Resume-from-pause MUST replay the burst (locked decision in the
        // approved plan, broader trigger than `dispatchStarted`).
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .paused, current: .printing)
        #expect(model.printingBurstToken == before &+ 1)
    }

    @Test
    func stoppedToPrintingBumpsToken() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .stopped, current: .printing)
        #expect(model.printingBurstToken == before &+ 1)
    }

    @Test
    func busyToPrintingBumpsToken() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .busy, current: .printing)
        #expect(model.printingBurstToken == before &+ 1)
    }

    @Test
    func readyToPrintingBumpsToken() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .ready, current: .printing)
        #expect(model.printingBurstToken == before &+ 1)
    }

    @Test
    func printingToPrintingDoesNotBump() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .printing, current: .printing)
        #expect(model.printingBurstToken == before)
    }

    @Test
    func printingToPausedDoesNotBump() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .printing, current: .paused)
        #expect(model.printingBurstToken == before)
    }

    @Test
    func idleToIdleDoesNotBump() {
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .idle, current: .idle)
        #expect(model.printingBurstToken == before)
    }

    @Test
    func firstObservationDoesNotBump() {
        // `previous == nil` means "no prior status observed yet". The
        // launch-while-printing burst is the controller's job (one-shot
        // `didPlayLaunchAnimation`), not the coordinator's, so the token
        // stays put on the very first poll.
        let (coordinator, model) = makeCoordinator()
        let before = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: nil, current: .printing)
        #expect(model.printingBurstToken == before)
    }

    @Test
    func sequentialTransitionsAccumulate() {
        let (coordinator, model) = makeCoordinator()
        let start = model.printingBurstToken
        coordinator.bumpPrintingBurstToken(previous: .idle, current: .printing)
        coordinator.bumpPrintingBurstToken(previous: .printing, current: .paused)
        coordinator.bumpPrintingBurstToken(previous: .paused, current: .printing)
        coordinator.bumpPrintingBurstToken(previous: .printing, current: .finished)
        coordinator.bumpPrintingBurstToken(previous: .finished, current: .idle)
        coordinator.bumpPrintingBurstToken(previous: .idle, current: .printing)
        #expect(model.printingBurstToken == start &+ 3)
    }
}
