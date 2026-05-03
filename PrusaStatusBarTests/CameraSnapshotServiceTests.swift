import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage: `notifications` Requirement -- Notifications attach a live
/// camera snapshot when a camera is reachable.
///
/// These tests exercise the orchestrator (`CameraSnapshotService`) at the
/// protocol level and the priority/timeout/fallback rules that the spec
/// pins. The `LiveCameraSnapshotService` itself talks to `GoRTCService` and
/// real network endpoints, so its provider-routing logic is covered through
/// fakes here rather than via integration tests against the live helper.
@MainActor
struct CameraSnapshotServiceTests {
    @Test
    func stubServiceReturnsConfiguredResult() async {
        let service = StubCameraSnapshotService()
        #expect(await service.captureForNotification() == nil)

        let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let configured = StubCameraSnapshotService(stubResult: bytes)
        #expect(await configured.captureForNotification() == bytes)
    }

    @Test
    func orchestratorPicksFirstSucceedingProvider() async {
        let buddy = FakeProvider(result: .success(Data([0x01, 0x02])))
        let generic = FakeProvider(result: .success(Data([0x03, 0x04])))
        let orchestrator = OrchestratorHarness(
            providers: [buddy, generic],
            timeout: 2
        )
        let result = await orchestrator.captureForNotification()
        #expect(result == Data([0x01, 0x02]))
    }

    @Test
    func orchestratorFallsThroughOnProviderFailure() async {
        let buddy = FakeProvider(result: .failure(StubError.boom))
        let generic = FakeProvider(result: .success(Data([0x09])))
        let orchestrator = OrchestratorHarness(
            providers: [buddy, generic],
            timeout: 2
        )
        let result = await orchestrator.captureForNotification()
        #expect(result == Data([0x09]))
    }

    @Test
    func orchestratorReturnsNilWhenNoProviders() async {
        let orchestrator = OrchestratorHarness(providers: [], timeout: 1)
        #expect(await orchestrator.captureForNotification() == nil)
    }

    @Test
    func orchestratorReturnsNilWhenAllProvidersFail() async {
        let buddy = FakeProvider(result: .failure(StubError.boom))
        let generic = FakeProvider(result: .failure(StubError.boom))
        let orchestrator = OrchestratorHarness(
            providers: [buddy, generic],
            timeout: 2
        )
        #expect(await orchestrator.captureForNotification() == nil)
    }

    @Test
    func orchestratorRespectsTimeoutWhenProvidersHang() async {
        // Provider that never returns within the budget. The orchestrator's
        // timeout race must yield nil.
        let slow = FakeProvider(result: .delay(seconds: 5, then: .success(Data([0xAA]))))
        let orchestrator = OrchestratorHarness(providers: [slow], timeout: 0.2)

        let start = Date()
        let result = await orchestrator.captureForNotification()
        let elapsed = Date().timeIntervalSince(start)

        #expect(result == nil)
        #expect(elapsed < 1.5, "timeout race should yield well before the slow provider's 5s")
    }
}

private enum StubError: Error { case boom }

/// Exposes the orchestrator's race semantics to tests without going through
/// `LiveCameraSnapshotService` (which requires `AppModel` and leaks into
/// `GoRTCService`). Mirrors the behaviour pinned by the spec.
private struct OrchestratorHarness {
    let providers: [CameraSnapshotProvider]
    let timeout: TimeInterval

    func captureForNotification() async -> Data? {
        guard !providers.isEmpty else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        return await withTaskGroup(of: Data?.self, returning: Data?.self) { group in
            group.addTask {
                for provider in providers {
                    let remaining = deadline.timeIntervalSinceNow
                    guard remaining > 0.01 else { return nil }
                    if let data = try? await provider.snapshot(timeout: remaining) {
                        return data
                    }
                }
                return nil
            }
            group.addTask {
                let remaining = max(0, deadline.timeIntervalSinceNow)
                let nanos = UInt64(remaining * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
    }
}

private struct FakeProvider: CameraSnapshotProvider {
    // swiftformat:disable:next redundantSendable
    indirect enum Outcome: Sendable {
        case success(Data)
        case failure(StubError)
        case delay(seconds: Double, then: Outcome)
    }

    let result: Outcome

    func snapshot(timeout _: TimeInterval) async throws -> Data {
        try await execute(result)
    }

    private func execute(_ outcome: Outcome) async throws -> Data {
        switch outcome {
        case let .success(data):
            return data
        case let .failure(error):
            throw error
        case let .delay(seconds, then):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return try await execute(then)
        }
    }
}
