import Foundation

/// Registry of live camera players so the popover / Quick Look keepalive can
/// stop any still-running stream when nothing visible needs it.
///
/// With the in-process VLC player, a tile or popup normally stops its own
/// player when SwiftUI unmounts the hosting view. This registry is the
/// explicit "stop everything" hook the keepalive calls in the same conditions
/// the old code used to stop the go2rtc helper (for example, the last Quick
/// Look popup closes while the popover is already closed). Each player
/// registers a stop closure when it starts and deregisters on teardown.
@MainActor
final class ActiveCameraPlayers {
    static let shared = ActiveCameraPlayers()

    private var stoppers: [ObjectIdentifier: () -> Void] = [:]

    func register(_ id: ObjectIdentifier, stop: @escaping () -> Void) {
        stoppers[id] = stop
    }

    func deregister(_ id: ObjectIdentifier) {
        stoppers[id] = nil
    }

    func stopAll() {
        // Snapshot then clear before invoking: avoids holding stale stop
        // handlers, and stays safe even if a stop closure deregisters mid-call
        // (mutating `stoppers` while iterating its values would trap).
        let toStop = stoppers.values
        stoppers.removeAll()
        for stop in toStop {
            stop()
        }
    }
}
