@testable import PrusaStatusBar
import Testing

/// Covers `menu-bar-ui` rule that the "Open PrusaLink" button is gated on
/// both `printerBaseURL` being set AND the printer being reachable.
struct DropdownPrusaLinkButtonGateTests {
    @Test
    func disabledWhenURLEmpty() {
        #expect(!DropdownView.shouldEnablePrusaLink(
            printerBaseURL: "",
            isDisconnected: false
        ))
    }

    @Test
    func disabledWhenURLOnlyWhitespace() {
        #expect(!DropdownView.shouldEnablePrusaLink(
            printerBaseURL: "   \n",
            isDisconnected: false
        ))
    }

    @Test
    func enabledWhenConfiguredAndReachable() {
        #expect(DropdownView.shouldEnablePrusaLink(
            printerBaseURL: "http://printer.local",
            isDisconnected: false
        ))
    }

    @Test
    func disabledWhenDisconnectedEvenIfURLConfigured() {
        #expect(!DropdownView.shouldEnablePrusaLink(
            printerBaseURL: "http://printer.local",
            isDisconnected: true
        ))
    }

    @Test
    func linksRowHiddenWhenBothTogglesOff() {
        #expect(!DropdownView.shouldRenderLinksRow(
            showPrusaLinkButton: false,
            showPrusaConnectButton: false
        ))
    }

    @Test
    func linksRowVisibleWhenPrusaLinkToggleOn() {
        #expect(DropdownView.shouldRenderLinksRow(
            showPrusaLinkButton: true,
            showPrusaConnectButton: false
        ))
    }

    @Test
    func linksRowVisibleWhenPrusaConnectToggleOn() {
        #expect(DropdownView.shouldRenderLinksRow(
            showPrusaLinkButton: false,
            showPrusaConnectButton: true
        ))
    }

    @Test
    func prusaConnectURLEmptyUUIDFallsBackToGenericDashboard() {
        let url = DropdownView.prusaConnectURL(uuid: "")
        #expect(url?.absoluteString == "https://connect.prusa3d.com")
    }

    @Test
    func prusaConnectURLWhitespaceUUIDFallsBackToGenericDashboard() {
        let url = DropdownView.prusaConnectURL(uuid: "   ")
        #expect(url?.absoluteString == "https://connect.prusa3d.com")
    }

    @Test
    func prusaConnectURLPopulatedUUIDDeepLinks() {
        let uuid = "199c3848-d807-437e-ad78-4d1b2519c463"
        let url = DropdownView.prusaConnectURL(uuid: uuid)
        #expect(url?.absoluteString == "https://connect.prusa3d.com/printer/\(uuid)/dashboard")
    }
}
