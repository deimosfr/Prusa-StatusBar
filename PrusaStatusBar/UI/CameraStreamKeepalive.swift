import Foundation

/// Tracks which camera Quick Look popup windows are currently open so the
/// menu bar popover delegate can defer stopping the camera players while at
/// least one popup is still streaming.
///
/// With the in-process VLC player, a tile or popup normally stops its own
/// player when SwiftUI unmounts the hosting view. This gate covers the case
/// where dismissing the popover would otherwise stop streams that a detached
/// popup window still needs: it only calls `stopPlayers` (wired to
/// `ActiveCameraPlayers.shared.stopAll`) when nothing visible remains.
///
/// Lifecycle:
/// - `register(_:)`   when a popup window is presented for a camera kind.
/// - `deregister(_:)` when that popup window closes.
/// - `popoverDidClose()` / detached-window mirrors so the keepalive can decide
///   whether to stop the players now (nothing open) or wait for the last
///   popup to close.
@MainActor
final class CameraStreamKeepalive {
    /// Stop closure injected for testability. Production wires it to
    /// `ActiveCameraPlayers.shared.stopAll`.
    private let stopPlayers: @MainActor () -> Void

    private var openPopups: Set<CameraTileKind> = []
    private var popoverVisible: Bool = false
    private var detachedWindowOpen: Bool = false

    init(stopPlayers: @escaping @MainActor () -> Void) {
        self.stopPlayers = stopPlayers
    }

    /// Number of currently registered popup windows. Exposed for tests.
    var popupCount: Int {
        openPopups.count
    }

    func register(_ kind: CameraTileKind) {
        openPopups.insert(kind)
    }

    func deregister(_ kind: CameraTileKind) {
        openPopups.remove(kind)
        // The last popup just closed and the popover is also closed, so
        // nothing in the app needs the players. Mirror the popover-close
        // teardown.
        if openPopups.isEmpty, !popoverVisible, !detachedWindowOpen {
            stopPlayers()
        }
    }

    func popoverDidShow() {
        popoverVisible = true
    }

    /// Called from `MenuBarPopoverDelegate.popoverDidClose`. Stops the camera
    /// players only when no popup or detached window is keeping them alive.
    func popoverDidClose() {
        popoverVisible = false
        if openPopups.isEmpty, !detachedWindowOpen {
            stopPlayers()
        }
    }

    /// Call BEFORE closing the popover when detaching to a window so the
    /// popover-close path does not stop the players mid-transition.
    func detachedWindowDidOpen() {
        detachedWindowOpen = true
    }

    func detachedWindowDidClose() {
        detachedWindowOpen = false
        if openPopups.isEmpty, !popoverVisible {
            stopPlayers()
        }
    }
}
