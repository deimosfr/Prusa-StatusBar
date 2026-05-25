import AppKit
import Observation
import SwiftUI

/// Owns the `NSStatusItem`. The label/icon are driven from `AppModel` via an
/// `Observation` tracking closure that re-runs whenever a tracked property
/// changes. Left-click opens the SwiftUI dropdown in an `NSPopover`.
@MainActor
public final class MenuBarController {
    let model: AppModel
    let coordinator: PollingCoordinator
    let openPreferences: () -> Void
    let openPrinterPreferences: () -> Void
    let customActionRunner: CustomActionRunning
    let notifier: NotificationService

    private let statusItem: NSStatusItem
    let popover: NSPopover
    private let popoverDelegate: MenuBarPopoverDelegate
    private var lastPresentation: StatusPresenter.MenuBarPresentation?

    /// Owns the camera Quick Look popup windows + the keepalive that
    /// defers go2rtc teardown while a popup is open.
    let cameraQuickLook: CameraQuickLookCoordinator

    /// Owns the detached status window that the user can open via the
    /// "Detach" footer button. Nil until first detach.
    let detachedWindowController: DetachedStatusWindowController

    /// Drives the bounded 2-cycle "printing" burst on the menu bar. Owned
    /// by the controller so it can be cancelled when the state leaves
    /// `.printing` mid-burst.
    let printingAnimator = PrintingIconAnimator()

    /// Last `printingBurstToken` value the controller observed. The
    /// `PollingCoordinator` bumps the token on every non-printing -> printing
    /// transition, so a strict-greater value here means "play a fresh
    /// burst now". Initialised to `0` so the first observation always
    /// matches the model's default zero (no burst on launch unless the
    /// `didPlayLaunchAnimation` path explicitly fires one).
    var lastSeenPrintingBurstToken: Int = 0

    /// One-shot flag for the launch-time burst. Set after the controller
    /// fires the burst on the first render where the printer is already
    /// printing, so re-renders during the same app process do not retrigger
    /// it.
    var didPlayLaunchAnimation: Bool = false

    public init(
        model: AppModel,
        coordinator: PollingCoordinator,
        openPreferences: @escaping () -> Void,
        openPrinterPreferences: @escaping () -> Void,
        customActionRunner: CustomActionRunning,
        notifier: NotificationService
    ) {
        self.model = model
        self.coordinator = coordinator
        self.openPreferences = openPreferences
        self.openPrinterPreferences = openPrinterPreferences
        self.customActionRunner = customActionRunner
        self.notifier = notifier
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        // Frame-resize animation disabled: when content size changes
        // (e.g. ActionsSection collapse), animating the popover frame
        // fights SwiftUI's own layout pass and visibly glitches AVPlayer
        // sublayers in CameraTile. Instant resize matches what users
        // expect from a menu-bar dropdown.
        popover.animates = false
        // Initial seed; SwiftUI hosting controller updates preferredContentSize
        // to the body's intrinsic size as soon as the view is installed.
        popover.contentSize = NSSize(width: 360, height: 1)

        let coordinator = CameraQuickLookCoordinator(stopGoRTC: { GoRTCService.shared.stop() })
        cameraQuickLook = coordinator
        // Route popover show/close into the keepalive so go2rtc only
        // tears down when no popup window is still streaming.
        popoverDelegate = MenuBarPopoverDelegate(
            model: model,
            onShow: { coordinator.keepalive.popoverDidShow() },
            onClose: { coordinator.keepalive.popoverDidClose() }
        )
        popover.delegate = popoverDelegate

        detachedWindowController = DetachedStatusWindowController(
            onShow: { [weak model] in
                guard let model else { return }
                // Unconditionally assert visible so cameras mount even if the
                // async popoverDidClose Task ran before present() returned.
                model.popoverShowToken &+= 1
                model.popoverVisible = true
            },
            onClose: { [weak model, weak coordinator] in
                model?.popoverVisible = false
                model?.detachedWindowVisible = false
                coordinator?.keepalive.detachedWindowDidClose()
            }
        )

        configureButton()
        scheduleRefresh()
        installPopoverContent()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        let placeholder = NSImage(named: StatusPresenter.AssetName.idle)
        placeholder?.isTemplate = true
        placeholder?.size = NSSize(width: 17, height: 17)
        placeholder?.accessibilityDescription = "Prusa StatusBar"
        button.image = placeholder
        button.title = ""
    }

    /// Re-render the menu-bar surface whenever the AppModel changes the
    /// inputs `StatusPresenter` consumes. We re-arm the tracker after each
    /// fire, Observation's `withObservationTracking` is single-shot.
    ///
    /// The recursion stays Swift-6-clean because `MenuBarController` is
    /// `@MainActor final class`, which makes `Self` implicitly `Sendable` and
    /// safe to capture in the `Task` re-arming closure.
    private func scheduleRefresh() {
        render()
        track()
    }

    private func track() {
        withObservationTracking {
            _ = model.lastStatus
            _ = model.lastError
            _ = model.consecutiveFailures
            _ = model.printerBaseURL
            _ = model.apiKeyConfigured
            _ = model.showRemainingTime
            _ = model.showPercentage
            _ = model.disconnectedIconStyle
            _ = model.disconnectedIconEmoji
            _ = model.printingBurstToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.render()
                self?.track()
            }
        }
    }

    private func render() {
        let presentation = StatusPresenter.present(
            status: model.lastStatus,
            isDisconnected: model.isDisconnected,
            isConfigured: model.isConfigured,
            showRemainingTime: model.showRemainingTime,
            showPercentage: model.showPercentage,
            disconnectedIconStyle: model.disconnectedIconStyle,
            disconnectedIconEmoji: model.disconnectedIconEmoji
        )

        guard let button = statusItem.button else {
            Log.menuBar.fault("NSStatusItem.button is nil, menu bar render skipped")
            return
        }

        // Animated-printing path: the burst is decoupled from the
        // `MenuBarPresentation` equality check below because the burst is
        // driven by `printingBurstToken` transitions, not by the
        // presentation value itself (which stays `.animatedPrinting` for
        // every printing render).
        if presentation.icon == .animatedPrinting {
            updatePrintingIcon(on: button)
            button.title = presentation.label.isEmpty ? "" : " \(presentation.label)"
            lastPresentation = presentation
            return
        }

        // Leaving `.printing`: cancel any in-flight burst so a stale frame
        // does not linger over the new state's icon.
        if lastPresentation?.icon == .animatedPrinting {
            printingAnimator.cancel()
        }

        if lastPresentation == presentation {
            return
        }
        lastPresentation = presentation

        button.image = makeImage(for: presentation)
        button.title = presentation.label.isEmpty ? "" : " \(presentation.label)"
    }

    private func makeImage(for presentation: StatusPresenter.MenuBarPresentation) -> NSImage? {
        switch presentation.icon {
        case let .asset(name):
            let image = NSImage(named: name)
            image?.isTemplate = true
            // Match the visual height of stock SF Symbol menu-bar icons
            // (wifi, sound, etc). The asset glyphs use a 24x24 viewBox
            // which renders ~10% taller than the system standard.
            image?.size = NSSize(width: 17, height: 17)
            return image
        case let .symbol(name):
            let scale = NSImage.SymbolConfiguration(scale: .medium)
            let configuration: NSImage.SymbolConfiguration = if let tint = presentation.tint {
                NSImage.SymbolConfiguration(paletteColors: [tint]).applying(scale)
            } else {
                scale
            }
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = (presentation.tint == nil)
            return image
        case .minimalDot:
            return Self.makeMinimalDotImage()
        case .empty:
            return Self.makeEmptyImage()
        case let .emoji(emoji):
            return Self.makeEmojiImage(emoji)
        case .animatedPrinting:
            // The animated path is handled directly in `render()` via
            // `updatePrintingIcon`; this branch is a defensive fallback so
            // the switch stays exhaustive. It applies the settled asset
            // without driving the animator (no button reference here).
            return PrintingIconAnimator.settledImage()
        }
    }

    /// 1x1 fully transparent NSImage used for the `.none` disconnected-icon
    /// style. Keeps the NSStatusItem button instantiated and hit-testable
    /// while taking the minimum possible width.
    private static func makeEmptyImage() -> NSImage {
        let canvasSize = NSSize(width: 1, height: 1)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Prusa StatusBar"
        return image
    }

    /// Renders a small filled circle as a template image so macOS tints it
    /// with the menu-bar foreground color. Sized small enough that the
    /// status item collapses to roughly the system minimum width.
    private static func makeMinimalDotImage() -> NSImage {
        let dotSize: CGFloat = 4
        let canvasSize = NSSize(width: dotSize, height: dotSize)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor.black.setFill()
        let rect = NSRect(origin: .zero, size: canvasSize)
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Prusa StatusBar"
        return image
    }

    /// Rasterises a user-chosen emoji into a 17pt NSImage (matching the
    /// asset glyph height) with `isTemplate = false` so the emoji's native
    /// colors are preserved.
    private static func makeEmojiImage(_ emoji: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 14)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = attributed.size()
        let height: CGFloat = 17
        let width = max(textSize.width, height)
        let canvasSize = NSSize(width: ceil(width), height: height)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        let drawRect = NSRect(
            x: (canvasSize.width - textSize.width) / 2,
            y: (canvasSize.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: drawRect)
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = "Prusa StatusBar"
        return image
    }

    @objc
    private func handleClick(_: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            openPreferences()
            return
        }
        if model.detachedWindowVisible {
            detachedWindowController.bringToFront()
            return
        }
        togglePopover(relativeTo: button)
    }

    private func togglePopover(relativeTo view: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            coordinator.refreshNow()
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Closes the transient popover and opens the content in a persistent
    /// floating `NSWindow`. Registers with the keepalive BEFORE closing
    /// the popover so the popover-close path does not tear down go2rtc.
    func detach() {
        cameraQuickLook.keepalive.detachedWindowDidOpen()
        // Set detachedWindowVisible BEFORE performClose so the async
        // handlePopoverDidClose Task sees it and skips clearing popoverVisible.
        model.detachedWindowVisible = true
        popover.performClose(nil)
        detachedWindowController.present(
            view: makeDropdownView(
                onDetach: nil,
                onContentResize: { [weak self] in self?.detachedWindowController.refit() }
            )
        )
    }
}

/// Bumps `AppModel.popoverShowToken` whenever the dropdown is shown so that
/// transient SwiftUI animations (e.g. the progress-bar sheen sweep) can
/// reset their per-open lifecycle. Also flips `popoverVisible` and tears
/// down the camera helper on close, so RTSP streaming and go2rtc do not
/// keep running while the menu bar is closed. The delegate must be an
/// `NSObject` because `NSPopoverDelegate` inherits `NSObjectProtocol`.
@MainActor
final class MenuBarPopoverDelegate: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let onShow: () -> Void
    private let onClose: () -> Void

    init(
        model: AppModel,
        onShow: @escaping () -> Void = {},
        onClose: @escaping () -> Void = { GoRTCService.shared.stop() }
    ) {
        self.model = model
        self.onShow = onShow
        self.onClose = onClose
        super.init()
    }

    func popoverDidShow(_: Notification) {
        Task { @MainActor in
            handlePopoverDidShow()
        }
    }

    func popoverDidClose(_: Notification) {
        Task { @MainActor in
            handlePopoverDidClose()
        }
    }

    /// Synchronous body of `popoverDidShow`, exposed for tests.
    func handlePopoverDidShow() {
        if !model.popoverVisible {
            model.popoverShowToken &+= 1
            model.popoverVisible = true
        }
        onShow()
    }

    /// Synchronous body of `popoverDidClose`, exposed for tests. Calls the
    /// injected `onClose` after flipping the visibility flag, so tests can
    /// observe the helper-stop call.
    func handlePopoverDidClose() {
        // When detaching, the window is already open and takes over the
        // "visible" contract. Clearing popoverVisible would unmount camera
        // tiles in the detached window and could crash AVPlayer cleanup.
        if !model.detachedWindowVisible {
            model.popoverVisible = false
        }
        // SwiftUI dismantling the CameraTile pauses AVPlayer, but the
        // helper subprocess keeps the upstream RTSP session warm unless
        // we explicitly stop it. Doing it here means zero camera-side
        // CPU and zero network bytes while the menu is closed.
        onClose()
    }
}
