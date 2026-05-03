@testable import PrusaStatusBar
import Testing

/// Covers `prusa-link-client` decoding of the `state` enum, including the
/// upstream `ATTTENTION` typo handling.
struct PrinterStateTests {
    @Test
    func uppercaseStandardValues() {
        #expect(PrinterState.decode("IDLE") == .idle)
        #expect(PrinterState.decode("PRINTING") == .printing)
        #expect(PrinterState.decode("PAUSED") == .paused)
        #expect(PrinterState.decode("FINISHED") == .finished)
        #expect(PrinterState.decode("STOPPED") == .stopped)
        #expect(PrinterState.decode("ERROR") == .error)
        #expect(PrinterState.decode("READY") == .ready)
        #expect(PrinterState.decode("BUSY") == .busy)
    }

    @Test
    func attentionTypoIsAccepted() {
        #expect(PrinterState.decode("ATTENTION") == .attention)
        #expect(PrinterState.decode("ATTTENTION") == .attention)
    }

    @Test
    func mixedCaseIsAccepted() {
        #expect(PrinterState.decode("Printing") == .printing)
        #expect(PrinterState.decode("paused") == .paused)
    }

    @Test
    func unknownValueFallsBackToIdle() {
        #expect(PrinterState.decode("GIBBERISH") == .idle)
    }

    @Test
    func isActiveCovers_printing_paused_busy_attention() {
        #expect(PrinterState.printing.isActive)
        #expect(PrinterState.paused.isActive)
        #expect(PrinterState.busy.isActive)
        #expect(PrinterState.attention.isActive)
        #expect(!PrinterState.idle.isActive)
        #expect(!PrinterState.finished.isActive)
    }
}
