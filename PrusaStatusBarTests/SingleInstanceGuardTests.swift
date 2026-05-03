import AppKit
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `single-instance` Requirement: Deny Duplicate Launch
/// - Scenarios "Second launch with existing instance" and "First launch with
///   no existing instance".
@MainActor
struct SingleInstanceGuardTests {
    @Test
    func returnsNilWhenNoOtherInstancesRunning() {
        let provider = FakeRunningInstancesProvider(returning: [])
        let delegate = AppDelegate()
        delegate.runningInstancesProvider = provider

        let result = delegate.existingInstance(forBundleID: "com.example.test")

        #expect(result == nil)
        #expect(provider.queriedBundleIdentifiers == ["com.example.test"])
    }

    @Test
    func returnsFirstRunningAppWhenOthersExist() {
        let standIn = NSRunningApplication.current
        let provider = FakeRunningInstancesProvider(returning: [standIn])
        let delegate = AppDelegate()
        delegate.runningInstancesProvider = provider

        let result = delegate.existingInstance(forBundleID: "com.example.test")

        #expect(result === standIn)
        #expect(provider.queriedBundleIdentifiers == ["com.example.test"])
    }

    @Test
    func returnsNilForNilBundleID() {
        let provider = FakeRunningInstancesProvider(returning: [NSRunningApplication.current])
        let delegate = AppDelegate()
        delegate.runningInstancesProvider = provider

        let result = delegate.existingInstance(forBundleID: nil)

        #expect(result == nil)
        #expect(provider.queriedBundleIdentifiers.isEmpty)
    }

    @Test
    func returnsNilForEmptyBundleID() {
        let provider = FakeRunningInstancesProvider(returning: [NSRunningApplication.current])
        let delegate = AppDelegate()
        delegate.runningInstancesProvider = provider

        let result = delegate.existingInstance(forBundleID: "")

        #expect(result == nil)
        #expect(provider.queriedBundleIdentifiers.isEmpty)
    }
}

@MainActor
private final class FakeRunningInstancesProvider: RunningInstancesProvider {
    private let stubbed: [NSRunningApplication]
    private(set) var queriedBundleIdentifiers: [String] = []

    init(returning stubbed: [NSRunningApplication]) {
        self.stubbed = stubbed
    }

    func otherInstances(bundleIdentifier: String) -> [NSRunningApplication] {
        queriedBundleIdentifiers.append(bundleIdentifier)
        return stubbed
    }
}
