import AppKit

/// Owns the per-kind `CameraQuickLookWindowController` instances and the
/// shared `CameraStreamKeepalive` they use to gate go2rtc teardown.
/// `MenuBarController` holds one of these and forwards tile zoom clicks
/// here so the controller's own body stays focused on menu-bar surface
/// concerns.
@MainActor
final class CameraQuickLookCoordinator {
    let keepalive: CameraStreamKeepalive
    private let controllers: [CameraTileKind: CameraQuickLookWindowController]

    init(stopGoRTC: @escaping @MainActor () -> Void) {
        let keepalive = CameraStreamKeepalive(stopGoRTC: stopGoRTC)
        self.keepalive = keepalive
        controllers = [
            .buddy: CameraQuickLookWindowController(kind: .buddy, keepalive: keepalive),
            .generic: CameraQuickLookWindowController(kind: .generic, keepalive: keepalive)
        ]
    }

    func open(kind: CameraTileKind, source: CameraQuickLookSource) {
        guard let controller = controllers[kind] else { return }
        controller.present(source: source, title: title(for: kind))
    }

    private func title(for kind: CameraTileKind) -> String {
        switch kind {
        case .buddy: L10n.t("dropdown.camera.quicklook.title")
        case .generic: L10n.t("dropdown.generic_camera.quicklook.title")
        }
    }
}
