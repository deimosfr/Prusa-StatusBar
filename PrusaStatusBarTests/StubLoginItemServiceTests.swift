@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `login-item` Requirement: Stub double models the SMAppService toggle
///   contract (enabled / disabled, persistent across reads) without touching
///   the real `SMAppService.mainApp`.
struct StubLoginItemServiceTests {
    @Test
    func defaultStartsDisabled() {
        let service = StubLoginItemService()
        #expect(service.currentStatus() == .disabled)
    }

    @Test
    func initiallyEnabledFlagApplies() {
        let service = StubLoginItemService(initiallyEnabled: true)
        #expect(service.currentStatus() == .enabled)
    }

    @Test
    func setEnabledTrueFlipsToEnabled() throws {
        let service = StubLoginItemService()
        try service.setEnabled(true)
        #expect(service.currentStatus() == .enabled)
    }

    @Test
    func setEnabledFalseFlipsBackToDisabled() throws {
        let service = StubLoginItemService(initiallyEnabled: true)
        try service.setEnabled(false)
        #expect(service.currentStatus() == .disabled)
    }

    @Test
    func togglesArePersistentAcrossReads() throws {
        let service = StubLoginItemService()
        try service.setEnabled(true)
        #expect(service.currentStatus() == .enabled)
        #expect(service.currentStatus() == .enabled)
        try service.setEnabled(false)
        #expect(service.currentStatus() == .disabled)
    }
}
