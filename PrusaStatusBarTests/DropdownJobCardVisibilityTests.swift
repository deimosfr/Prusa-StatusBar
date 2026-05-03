@testable import PrusaStatusBar
import Testing

/// Covers `menu-bar-ui` rule that the JobCard (rows 2 and 3 of the dropdown)
/// renders only for printer states where progress data is meaningful.
struct DropdownJobCardVisibilityTests {
    @Test
    func showsForActivePrintStates() {
        #expect(DropdownView.shouldShowJobCard(state: .printing))
        #expect(DropdownView.shouldShowJobCard(state: .paused))
        #expect(DropdownView.shouldShowJobCard(state: .attention))
        #expect(DropdownView.shouldShowJobCard(state: .finished))
    }

    @Test
    func hidesForInactiveStates() {
        #expect(!DropdownView.shouldShowJobCard(state: .idle))
        #expect(!DropdownView.shouldShowJobCard(state: .ready))
        #expect(!DropdownView.shouldShowJobCard(state: .busy))
        #expect(!DropdownView.shouldShowJobCard(state: .stopped))
        #expect(!DropdownView.shouldShowJobCard(state: .error))
    }

    @Test
    func everyEnumCaseIsCovered() {
        for state in PrinterState.allCases {
            _ = DropdownView.shouldShowJobCard(state: state)
        }
    }
}
