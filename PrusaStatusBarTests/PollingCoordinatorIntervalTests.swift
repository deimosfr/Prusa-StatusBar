import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `polling` Requirement: Background polling refreshes status on a
///   user-configurable interval (connected vs disconnected branch)
@MainActor
struct PollingCoordinatorIntervalTests {
    private func makeCoordinator() -> (PollingCoordinator, AppModel) {
        let model = AppModel()
        let client = StubPrusaLinkClient(phase: .idle)
        let notifier = StubNotificationService()
        let coordinator = PollingCoordinator(model: model, client: client, notifier: notifier)
        return (coordinator, model)
    }

    @Test
    func usesConnectedIntervalWhenReachable() {
        let (coordinator, model) = makeCoordinator()
        model.refreshIntervalSeconds = 15
        model.disconnectedRefreshIntervalSeconds = 600
        model.lastError = nil
        model.consecutiveFailures = 0

        #expect(coordinator.computeNextInterval() == 15)
    }

    @Test
    func usesDisconnectedIntervalAfterTwoConsecutiveFailures() {
        let (coordinator, model) = makeCoordinator()
        model.refreshIntervalSeconds = 5
        model.disconnectedRefreshIntervalSeconds = 120
        model.lastError = .unreachable
        model.consecutiveFailures = 2

        #expect(model.isDisconnected)
        #expect(coordinator.computeNextInterval() == 120)
    }

    @Test
    func singleFailureStaysOnConnectedInterval() {
        let (coordinator, model) = makeCoordinator()
        model.refreshIntervalSeconds = 5
        model.disconnectedRefreshIntervalSeconds = 120
        model.lastError = .unreachable
        model.consecutiveFailures = 1

        #expect(model.isDisconnected == false)
        #expect(coordinator.computeNextInterval() == 5)
    }

    @Test
    func clampsOutOfRangeMirrorOnConnected() {
        let (coordinator, model) = makeCoordinator()
        model.refreshIntervalSeconds = 99999
        model.lastError = nil
        model.consecutiveFailures = 0

        #expect(coordinator.computeNextInterval() == TimeInterval(UserPreferences.refreshIntervalMax))
    }

    @Test
    func clampsOutOfRangeMirrorOnDisconnected() {
        let (coordinator, model) = makeCoordinator()
        model.disconnectedRefreshIntervalSeconds = 99999
        model.lastError = .unreachable
        model.consecutiveFailures = 5

        #expect(
            coordinator.computeNextInterval()
                == TimeInterval(UserPreferences.disconnectedRefreshIntervalMax)
        )
    }
}
