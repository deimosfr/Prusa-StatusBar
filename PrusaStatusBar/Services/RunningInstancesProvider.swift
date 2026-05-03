import AppKit

/// Protocol over `NSRunningApplication.runningApplications(withBundleIdentifier:)`
/// so the duplicate-launch guard in `AppDelegate` can be unit-tested with a
/// fake.
@MainActor
protocol RunningInstancesProvider {
    /// Returns every running application matching `bundleIdentifier` other
    /// than the current process.
    func otherInstances(bundleIdentifier: String) -> [NSRunningApplication]
}

@MainActor
struct SystemRunningInstancesProvider: RunningInstancesProvider {
    func otherInstances(bundleIdentifier: String) -> [NSRunningApplication] {
        let currentPID = NSRunningApplication.current.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }
    }
}
