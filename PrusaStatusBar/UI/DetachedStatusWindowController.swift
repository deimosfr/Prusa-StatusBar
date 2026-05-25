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
///
/// `refit()` re-runs that same poll while the window stays open, so the
/// window tracks content-height changes (e.g. a print finishing then a new
/// print starting) instead of freezing at its open-time height -- issue #19.
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

    /// Re-fit the open detached window to the current `DropdownView`
    /// content height. Invoked when the content reports a height change
    /// (e.g. a print finishing then a new print starting -- issue #19).
    /// Safe no-op when no window is open. Re-uses the one-way
    /// `fitWindowToContent` poll, so it cannot start a layout loop:
    /// `sizeThatFits` is measured against a fixed box and is independent of
    /// the window's own height, so our `setFrame` never feeds back in.
    func refit() {
        guard let host else { return }
        fitWindowToContent(hosting: host)
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
                if let frame = Self.refittedFrame(
                    current: w.frame,
                    fittedHeight: fitted.height,
                    maxHeight: maxH
                ) {
                    w.setFrame(frame, display: true, animate: false)
                }
            }
            self?.sizingTask = nil
        }
    }

    /// Computes the re-fitted window frame for a freshly measured content
    /// height. Keeps the window's top edge anchored (the window grows or
    /// shrinks downward), clamps the height to `maxHeight`, and returns
    /// `nil` when the resulting height is within 0.5 pt of the current
    /// frame -- no resize worth a layout pass. Pure + `nonisolated` so the
    /// height math is unit-testable without standing up an `NSWindow`.
    nonisolated static func refittedFrame(
        current: NSRect,
        fittedHeight: CGFloat,
        maxHeight: CGFloat
    ) -> NSRect? {
        let height = min(fittedHeight, maxHeight)
        guard abs(current.height - height) > 0.5 else { return nil }
        var frame = current
        frame.origin.y += frame.height - height
        frame.size.height = height
        return frame
    }
}
