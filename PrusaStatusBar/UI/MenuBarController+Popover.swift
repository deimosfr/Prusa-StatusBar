import AppKit
import SwiftUI

extension MenuBarController {
    /// Builds a fully wired `DropdownView`. Pass `onDetach` to show the
    /// "Detach" footer button (popover context); pass `nil` to hide it
    /// (detached window context, where nesting would be circular). Pass
    /// `onContentResize` for the detached window so it re-fits when the
    /// content height changes (issue #19); the popover leaves the no-op
    /// default since it auto-sizes via `NSHostingController.sizingOptions`.
    func makeDropdownView(
        onDetach: (() -> Void)? = nil,
        onContentResize: @escaping @MainActor () -> Void = {}
    ) -> DropdownView {
        var view = DropdownView(
            model: model,
            onRefresh: { [weak self] in self?.coordinator.refreshNow() },
            onPreferences: { [weak self] in self?.openPreferences() },
            onConfigurePrinter: { [weak self] in self?.openPrinterPreferences() },
            onQuit: { NSApp.terminate(nil) },
            onOpenPrusaLink: { [weak self] in self?.openPrusaLink() },
            onOpenPrusaConnect: { [weak self] in self?.openPrusaConnect() },
            onResume: { [weak self] in self?.coordinator.resumeCurrentJob() },
            onPause: { [weak self] in self?.coordinator.pauseCurrentJob() },
            onStop: { [weak self] in self?.coordinator.stopCurrentJob() }
        )
        view.onOpenRelease = { [weak self] in self?.openLatestRelease() }
        view.onRunCustomAction = { [weak self] slot in
            guard let self else { return .failure(.slotMissingConfig) }
            return await runCustomAction(slot)
        }
        view.onZoomCamera = { [weak self] kind, source in
            self?.cameraQuickLook.open(kind: kind, source: source)
        }
        view.onDetach = onDetach
        view.onContentResize = onContentResize
        return view
    }

    /// Builds the popover's `NSHostingController<DropdownView>` once at
    /// init time. The hosting controller stays mounted for the app's
    /// lifetime so scroll position and other SwiftUI `@State` survive
    /// close/reopen. CPU drain from periodic `TimelineView` / `Timer`
    /// updates inside the dropdown is gated on `model.popoverVisible`
    /// at the leaf views (HeroHeader, ProgressBarPremium, StatusPill)
    /// instead of by tearing down the tree.
    func installPopoverContent() {
        let view = makeDropdownView(onDetach: { [weak self] in self?.detach() })
        let host = NSHostingController(rootView: view)
        // Track SwiftUI body's fitting size so the popover both grows AND
        // shrinks when content size changes (e.g. ActionsSection collapse).
        // Without this, NSPopover keeps its widest-ever frame.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    func openPrusaLink() {
        let raw = model.printerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func openPrusaConnect() {
        guard let url = DropdownView.prusaConnectURL(uuid: model.prusaConnectUUID) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLatestRelease() {
        let fallback = URL(string: "https://github.com/deimosfr/Prusa-StatusBar/releases/latest")
        let url = model.availableUpdate?.htmlURL ?? fallback
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
