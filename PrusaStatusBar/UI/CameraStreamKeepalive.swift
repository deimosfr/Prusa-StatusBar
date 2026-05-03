import Foundation

/// Tracks which camera Quick Look popup windows are currently open so the
/// menu bar popover delegate can defer go2rtc teardown while at least one
/// popup is still streaming.
///
/// Without this gate, dismissing the popover would call
/// `GoRTCService.shared.stop()` (see `MenuBarPopoverDelegate.onClose`) and
/// kill the HLS stream feeding any popup window the user has detached.
///
/// Lifecycle:
/// - `register(_:)`  when a popup window is presented for a camera kind.
/// - `deregister(_:)` when that popup window closes.
/// - `popoverDidClose()` mirror so the keepalive can decide whether to
///   stop go2rtc immediately (no popups) or wait for the last popup to
///   close.
@MainActor
final class CameraStreamKeepalive {
    /// Stop closure injected for testability. Production wires it to
    /// `GoRTCService.shared.stop`.
    private let stopGoRTC: @MainActor () -> Void

    private var openPopups: Set<CameraTileKind> = []
    private var popoverVisible: Bool = false

    init(stopGoRTC: @escaping @MainActor () -> Void) {
        self.stopGoRTC = stopGoRTC
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
        // nothing in the app needs the helper. Mirror the original
        // popover-close teardown.
        if openPopups.isEmpty, !popoverVisible {
            stopGoRTC()
        }
    }

    func popoverDidShow() {
        popoverVisible = true
    }

    /// Called from `MenuBarPopoverDelegate.popoverDidClose`. Tears down
    /// go2rtc only when no popup is keeping it alive.
    func popoverDidClose() {
        popoverVisible = false
        if openPopups.isEmpty {
            stopGoRTC()
        }
    }
}
