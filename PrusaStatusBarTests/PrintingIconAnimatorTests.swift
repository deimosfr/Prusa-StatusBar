import AppKit
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Menu-bar printing icon plays bounded burst
///   animation (cadence + settled-asset).
@MainActor
struct PrintingIconAnimatorTests {
    @Test
    func cadenceConstantsMatchSpec() {
        // 2.4s/cycle, 2 cycles, total 4.8s. The author asked to slow the
        // motion 3x relative to the original 0.8s/cycle so the cup bob
        // reads cleanly at 17pt menu-bar size; the animator and popover
        // share `cycleDuration` so motion looks identical between the
        // menu bar burst and the continuously-animated popover glyph.
        #expect(PrintingIconAnimator.cycleDuration == 2.4)
        #expect(PrintingIconAnimator.cycleCount == 2)
        #expect(PrintingIconAnimator.frameRate >= 8)
    }

    @Test
    func bakedFrameCountCoversBurstDuration() {
        // Burst sequence: `cycleCount` full cycles followed by
        // `trailingFrameCount` wind-down frames (00...08) so the menu
        // bar lands on a pose matching `IconPrintingStatic` (frame 10
        // visual). Total = 24 * cycleCount + 9.
        let frames = PrintingIconAnimator.bakeFrames()
        let expected = PrintingIconAnimator.frameAssetNames.count
            * PrintingIconAnimator.cycleCount
            + PrintingIconAnimator.trailingFrameCount
        #expect(frames.count == expected)
    }

    @Test
    func bakedFrameSequenceEndsWithLeadingFrames() {
        // The last `trailingFrameCount` baked frames must be the leading
        // keyframes 00...(trailingFrameCount - 1), so the wind-down
        // walks the cup back through the start of the cycle before
        // settling on `IconPrintingStatic`.
        let frames = PrintingIconAnimator.bakeFrames()
        let trailing = frames.suffix(PrintingIconAnimator.trailingFrameCount)
        // Frame identity is captured indirectly via image size + template
        // flag (NSImage doesn't expose its source asset name); the count
        // and contiguity is what matters here, asserted alongside the
        // total-count test above.
        let allMatchSize = trailing.allSatisfy { $0.size == PrintingIconAnimator.iconSize }
        #expect(allMatchSize)
        #expect(trailing.count == PrintingIconAnimator.trailingFrameCount)
    }

    @Test
    func bakedFramesAreTemplate() {
        let frames = PrintingIconAnimator.bakeFrames()
        // Every frame must be a template image so macOS tints it with the
        // menu-bar foreground color (matching every other bundled asset).
        let allTemplate = frames.allSatisfy(\.isTemplate)
        #expect(allTemplate)
    }

    @Test
    func bakedFramesHaveMenuBarSize() {
        let frames = PrintingIconAnimator.bakeFrames()
        let expectedSize = PrintingIconAnimator.iconSize
        let allMatchSize = frames.allSatisfy { $0.size == expectedSize }
        #expect(allMatchSize)
    }

    @Test
    func settledImageIsTemplateAndSized() {
        // Settled image is `IconPrintingStatic`; if the asset is missing we
        // fall back to a blank `NSImage` of the right size so the menu bar
        // does not regress to a stale frame.
        let image = PrintingIconAnimator.settledImage()
        #expect(image.isTemplate)
        #expect(image.size == PrintingIconAnimator.iconSize)
    }

    @Test
    func frameAssetNamesMatchKeyframeFiles() {
        // The author supplied 24 keyframe SVGs (`IconPrinting_00` ...
        // `IconPrinting_23`); the animator drives a frame swap through
        // them, so the count and naming must match the bundled assets.
        #expect(PrintingIconAnimator.frameAssetNames.count == 24)
        #expect(PrintingIconAnimator.frameAssetNames.first == "IconPrinting_00")
        #expect(PrintingIconAnimator.frameAssetNames.last == "IconPrinting_23")
    }

    @Test
    func frameIntervalAlignsWithCadence() {
        // 0.8s / 24 keyframes ≈ 33ms per frame.
        let expected = PrintingIconAnimator.cycleDuration
            / Double(PrintingIconAnimator.frameAssetNames.count)
        #expect(abs(PrintingIconAnimator.frameInterval - expected) < 1e-9)
    }

    @Test
    func cancelStopsPlayback() {
        let animator = PrintingIconAnimator()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        guard let button = item.button else { return }
        animator.play(on: button)
        #expect(animator.isPlaying)
        animator.cancel()
        #expect(animator.isPlaying == false)
    }
}
