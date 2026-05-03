import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Dropdown exposes a collapsible Job Actions
///   section
///
/// The matrix lives on `ActionsSection.isEnabled(_:for:)` so it can be
/// asserted without standing up SwiftUI.
struct ActionsSectionTests {
    @Test
    func resumeEnabledOnlyInPaused() {
        for state in PrinterState.allCases {
            let enabled = ActionsSection.isEnabled(.resume, for: state)
            #expect(enabled == (state == .paused))
        }
    }

    @Test
    func pauseEnabledOnlyInPrinting() {
        for state in PrinterState.allCases {
            let enabled = ActionsSection.isEnabled(.pause, for: state)
            #expect(enabled == (state == .printing))
        }
    }

    @Test
    func stopEnabledInActiveOrAttention() {
        let active: Set<PrinterState> = [.printing, .paused, .attention]
        for state in PrinterState.allCases {
            let enabled = ActionsSection.isEnabled(.stop, for: state)
            #expect(enabled == active.contains(state))
        }
    }
}
