import AppKit

extension MenuBarController {
    /// Decides whether to play a 2-cycle burst or just render the settled
    /// `IconPrintingStatic` asset. Burst triggers:
    ///   - `printingBurstToken` advanced past `lastSeenPrintingBurstToken`
    ///     (a non-printing -> printing transition observed by the
    ///     `PollingCoordinator`),
    ///   - OR the very first render-while-printing in this app process
    ///     (`didPlayLaunchAnimation == false`), which covers the
    ///     "launch while a print is already running" case.
    /// Otherwise the static asset is applied directly.
    func updatePrintingIcon(on button: NSStatusBarButton) {
        let token = model.printingBurstToken
        let tokenAdvanced = token > lastSeenPrintingBurstToken
        let launchTrigger = !didPlayLaunchAnimation
        if tokenAdvanced || launchTrigger {
            lastSeenPrintingBurstToken = token
            didPlayLaunchAnimation = true
            printingAnimator.play(on: button)
            return
        }
        // Steady-state printing render (no fresh trigger): make sure no
        // stale burst is running and apply the settled asset.
        if printingAnimator.isPlaying {
            return
        }
        button.image = PrintingIconAnimator.settledImage()
    }
}
