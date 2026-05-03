import AppKit
import SwiftUI

/// Side-effect of bringing a freshly configured window on screen. Injected
/// so tests can swap in a no-op and avoid a real window appearing during
/// `xcodebuild test`.
typealias CameraQuickLookActivator = @MainActor (NSWindow) -> Void

/// Owns the lifecycle of one camera Quick Look popup `NSWindow`. There is
/// one controller per `CameraTileKind` (`.buddy`, `.generic`) so the two
/// cameras have independent windows that can be open simultaneously.
///
/// Mirrors `PreferencesWindowController` in shape: `present(...)` either
/// creates a new window or brings the existing one to the front; the
/// window's frame is autosaved so AppKit remembers position and size
/// across opens.
@MainActor
final class CameraQuickLookWindowController: NSObject, NSWindowDelegate {
    private let kind: CameraTileKind
    private let keepalive: CameraStreamKeepalive
    private let activate: CameraQuickLookActivator
    /// Visible to `@testable import` so unit tests can drive
    /// `windowWillClose(_:)` with a notification carrying the right
    /// window object. Production code outside the controller does not
    /// touch this.
    private(set) var window: NSWindow?
    private var host: NSHostingController<CameraQuickLookView>?
    private(set) var currentSource: CameraQuickLookSource?

    init(
        kind: CameraTileKind,
        keepalive: CameraStreamKeepalive,
        activate: @escaping CameraQuickLookActivator = { window in
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.kind = kind
        self.keepalive = keepalive
        self.activate = activate
        super.init()
    }

    /// Open the popup for `source`, or bring the existing window to the
    /// front and update its content if the source has changed.
    func present(source: CameraQuickLookSource, title: String) {
        if let window {
            if currentSource != source {
                let newView = CameraQuickLookView(source: source)
                host?.rootView = newView
                currentSource = source
            }
            window.title = title
            activate(window)
            return
        }

        let view = CameraQuickLookView(source: source)
        let hosting = NSHostingController(rootView: view)
        let newWindow = CameraQuickLookWindow(contentViewController: hosting)
        newWindow.title = title
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 720, height: 540))
        newWindow.contentMinSize = NSSize(width: 320, height: 240)
        newWindow.level = .floating
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        newWindow.delegate = self
        newWindow.setFrameAutosaveName("CameraQuickLook.\(kind.rawValue)")
        // First-run only: AppKit applies the autosaved frame when a name
        // is set, falling back to the geometry above if no autosave entry
        // exists. Center on first open so we are not stuck at (0, 0).
        if newWindow.frameAutosaveName.isEmpty || !newWindow.setFrameUsingName(newWindow.frameAutosaveName) {
            newWindow.center()
        }

        window = newWindow
        host = hosting
        currentSource = source
        keepalive.register(kind)

        activate(newWindow)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        host = nil
        currentSource = nil
        keepalive.deregister(kind)
    }
}

/// `NSWindow` subclass that closes on Spacebar to mimic Finder Quick Look.
/// ESC and the close button are handled by the standard responder chain.
final class CameraQuickLookWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        // 49 is the virtual keycode for Spacebar.
        if event.keyCode == 49 {
            performClose(self)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
