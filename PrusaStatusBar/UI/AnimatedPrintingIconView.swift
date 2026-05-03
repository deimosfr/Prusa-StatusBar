import AppKit
import SwiftUI

/// Drives the popover printing-icon animation by cycling through a fixed
/// sequence of pre-rendered keyframe assets (`IconPrinting_00` ...
/// `IconPrinting_23`). NSImage cannot animate the SMIL inside a single
/// SVG, so we frame-swap on a `Timer` instead. Same approach the menu-bar
/// burst (`PrintingIconAnimator`) uses, just looped continuously while
/// the popover is visible.
@MainActor
final class PrintingFrameTicker: ObservableObject {
    @Published var frameIndex: Int = 0
    let cycleDuration: Double
    let frameCount: Int
    private var timer: Timer?

    init(cycleDuration: Double, frameCount: Int) {
        self.cycleDuration = cycleDuration
        self.frameCount = frameCount
    }

    // No deinit cleanup: Swift 6 strict concurrency forbids touching the
    // non-Sendable `Timer` from a nonisolated deinit. The view calls
    // `stop()` from `onDisappear`.

    func start() {
        guard timer == nil, frameCount > 0 else { return }
        let interval = cycleDuration / Double(frameCount)
        let total = frameCount
        let scheduled = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frameIndex = (self.frameIndex + 1) % total
            }
        }
        // `.common` mode keeps the timer firing while the user is
        // tracking a menu / popover (default mode is paused during
        // event tracking on macOS).
        RunLoop.main.add(scheduled, forMode: .common)
        timer = scheduled
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

public struct AnimatedPrintingIconView: View {
    /// Cycle length in seconds. Defaults to 0.8s to match the menu-bar
    /// burst cadence (2 cycles, 1.6s total).
    public var cycleDuration: Double

    @StateObject private var ticker: PrintingFrameTicker

    public init(cycleDuration: Double = 2.4) {
        self.cycleDuration = cycleDuration
        _ticker = StateObject(
            wrappedValue: PrintingFrameTicker(
                cycleDuration: cycleDuration,
                frameCount: PrintingIconAnimator.frameAssetNames.count
            )
        )
    }

    public var body: some View {
        // No explicit foregroundStyle: the popover host (`StatusPill`)
        // applies a state-specific tint to the whole HStack, and the
        // template `Image` inherits it.
        Image(PrintingIconAnimator.frameAssetNames[ticker.frameIndex])
            .renderingMode(.template)
            .interpolation(.high)
            .resizable()
            .scaledToFit()
            .onAppear { ticker.start() }
            .onDisappear { ticker.stop() }
    }
}
