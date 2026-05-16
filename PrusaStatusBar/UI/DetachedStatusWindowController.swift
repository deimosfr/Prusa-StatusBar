import AppKit
import SwiftUI

/// Owns the lifecycle of the detached status `NSWindow` that the user
/// can open via the "Detach" footer button. The window hosts the same
/// `DropdownView` content as the popover but is NOT transient -- it
/// stays on screen when the user clicks elsewhere.
///
/// Mirrors `CameraQuickLookWindowController` in shape: `present(view:)`
/// creates a new window on first call or brings the existing one to the
/// front. The frame is NOT autosaved: every detach centers on the active
/// screen and sizes height to current content via a few timed
/// `sizeThatFits` polls (cheap, one-way, no layout loop).
@MainActor
final class DetachedStatusWindowController: NSObject, NSWindowDelegate {
    private let onShow: () -> Void
    private let onClose: () -> Void
    private(set) var window: NSWindow?
    private var host: NSHostingController<DropdownView>?
    private var sizingTask: Task<Void, Never>?

    init(onShow: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onShow = onShow
        self.onClose = onClose
        super.init()
    }

    /// Present the detached window. Creates a new window if none exists;
    /// brings the existing one to front otherwise (updating its root view
    /// to reflect the latest closure bindings).
    func present(view: DropdownView) {
        if let window {
            host?.rootView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: view)
        // Do NOT set hosting.sizingOptions = [.preferredContentSize]:
        // SwiftUI animations and async state changes can re-trigger the
        // preferred size update, which AppKit then re-applies to the window,
        // which re-triggers layout -- a loop that crashes. We poll size
        // manually instead (see fitWindowToContent), which is one-way.
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.contentViewController = hosting
        newWindow.contentMinSize = NSSize(width: 360, height: 200)
        newWindow.level = .floating
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        newWindow.delegate = self
        newWindow.center()

        window = newWindow
        host = hosting
        onShow()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        fitWindowToContent(hosting: hosting)
    }

    func bringToFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        sizingTask?.cancel()
        sizingTask = nil
        window = nil
        host = nil
        onClose()
    }

    /// Poll the hosting controller's fitted size at a few timed offsets and
    /// resize the window to match. Multiple passes catch late-mounting
    /// content (camera tiles, status sections that depend on async data).
    /// One-way: we read `sizeThatFits`, we write the window frame -- no KVO,
    /// no `sizingOptions` binding, so no layout loop.
    private func fitWindowToContent(hosting: NSHostingController<DropdownView>) {
        sizingTask?.cancel()
        sizingTask = Task { @MainActor [weak self] in
            let delaysMs: [UInt64] = [0, 80, 250, 600]
            for delay in delaysMs {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000)
                }
                if Task.isCancelled { return }
                guard let self, let w = window, host === hosting else { return }
                let fitted = hosting.sizeThatFits(in: NSSize(width: 360, height: 10000))
                guard fitted.height > 50 else { continue }
                let maxH = (w.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900) - 100
                let height = min(fitted.height, maxH)
                if abs(w.frame.height - height) > 0.5 {
                    var frame = w.frame
                    frame.origin.y += frame.height - height
                    frame.size.height = height
                    w.setFrame(frame, display: true, animate: false)
                }
            }
            self?.sizingTask = nil
        }
    }
}
