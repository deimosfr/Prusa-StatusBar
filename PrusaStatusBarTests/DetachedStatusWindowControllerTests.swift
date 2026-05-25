import AppKit
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Detached window re-fits to content height
///   changes
///   - Scenario "New print starts while detached window is open"
///   - Scenario "Content shrinks while detached window is open"
///   - Scenario "Re-fit keeps the top edge anchored"
///   - Scenario "Re-fit caps height to the visible screen"
struct DetachedStatusWindowControllerTests {
    /// New print -> taller content: the window grows downward while its top
    /// edge (`maxY`, since macOS frames are bottom-left origin) stays put.
    @Test
    func refitGrowsWindowDownwardKeepingTopAnchored() throws {
        let current = NSRect(x: 100, y: 500, width: 360, height: 400)

        let frame = try #require(
            DetachedStatusWindowController.refittedFrame(
                current: current,
                fittedHeight: 480,
                maxHeight: 900
            )
        )

        #expect(frame.size.height == 480)
        #expect(frame.size.width == current.size.width)
        #expect(frame.maxY == current.maxY) // top edge anchored
        #expect(frame.minY < current.minY) // grew downward
    }

    /// Printer returns to idle -> shorter content: the window shrinks from
    /// the bottom, top edge still anchored.
    @Test
    func refitShrinksWindowKeepingTopAnchored() throws {
        let current = NSRect(x: 100, y: 500, width: 360, height: 400)

        let frame = try #require(
            DetachedStatusWindowController.refittedFrame(
                current: current,
                fittedHeight: 250,
                maxHeight: 900
            )
        )

        #expect(frame.size.height == 250)
        #expect(frame.maxY == current.maxY) // top edge anchored
        #expect(frame.minY > current.minY) // shrank from the bottom
    }

    /// Content taller than the visible screen is clamped to `maxHeight`.
    @Test
    func refitClampsHeightToMax() {
        let current = NSRect(x: 0, y: 0, width: 360, height: 400)

        let result = DetachedStatusWindowController.refittedFrame(
            current: current,
            fittedHeight: 2000,
            maxHeight: 700
        )

        #expect(result?.size.height == 700)
    }

    /// A sub-0.5 pt height delta is not worth a resize: returns nil so the
    /// caller skips `setFrame`.
    @Test
    func refitReturnsNilForNegligibleDelta() {
        let current = NSRect(x: 0, y: 0, width: 360, height: 400)

        #expect(
            DetachedStatusWindowController.refittedFrame(
                current: current,
                fittedHeight: 400.3,
                maxHeight: 900
            ) == nil
        )
        #expect(
            DetachedStatusWindowController.refittedFrame(
                current: current,
                fittedHeight: 400,
                maxHeight: 900
            ) == nil
        )
    }
}
