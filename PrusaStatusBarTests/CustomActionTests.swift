import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - Round-trip of the public + secrets persistence halves and the
///   reassembly that the dropdown / preferences depend on.
/// - Visibility resolver matrix per the menu-bar-ui delta.
struct CustomActionTests {
    @Test
    func splitAndReassembleRoundTrip() {
        let id1 = UUID()
        let id2 = UUID()
        let original = CustomActionConfig(
            enabled: true,
            name: "Power on",
            symbol: "power",
            method: .post,
            visibility: .whenDisconnected,
            confirmBeforeRun: true,
            url: "https://homeassistant.local/api/services/switch/turn_on?token=abc",
            headers: [
                CustomActionHeader(id: id1, name: "Authorization", value: "Bearer xyz"),
                CustomActionHeader(id: id2, name: "X-Trace", value: "")
            ],
            body: "{\"entity_id\":\"switch.printer\"}"
        )

        let (pub, secrets) = original.split()
        let reassembled = CustomActionConfig.assemble(public: pub, secrets: secrets)

        #expect(reassembled.enabled == original.enabled)
        #expect(reassembled.name == original.name)
        #expect(reassembled.symbol == original.symbol)
        #expect(reassembled.method == original.method)
        #expect(reassembled.visibility == original.visibility)
        #expect(reassembled.confirmBeforeRun == original.confirmBeforeRun)
        #expect(reassembled.url == original.url)
        #expect(reassembled.body == original.body)
        #expect(reassembled.headers.count == 2)
        #expect(reassembled.headers[0].id == id1)
        #expect(reassembled.headers[0].name == "Authorization")
        #expect(reassembled.headers[0].value == "Bearer xyz")
        #expect(reassembled.headers[1].id == id2)
        #expect(reassembled.headers[1].name == "X-Trace")
        #expect(reassembled.headers[1].value == "")
    }

    @Test
    func reassembleWithMissingSecretsFallsBackToBlanks() {
        let pub = CustomActionPublicConfig(
            enabled: true,
            name: "X",
            symbol: "bolt",
            method: .get,
            visibility: .always,
            confirmBeforeRun: false,
            headerNames: [.init(id: UUID(), name: "X-One")]
        )
        let reassembled = CustomActionConfig.assemble(public: pub, secrets: nil)
        #expect(reassembled.enabled)
        #expect(reassembled.url == "")
        #expect(reassembled.body == "")
        #expect(reassembled.headers.first?.name == "X-One")
        #expect(reassembled.headers.first?.value == "")
    }

    @Test
    func publicConfigCodableRoundTrip() throws {
        let id = UUID()
        let original = CustomActionPublicConfig(
            enabled: true,
            name: "Test",
            symbol: "lightbulb.fill",
            method: .delete,
            visibility: .whenConnected,
            confirmBeforeRun: true,
            headerNames: [.init(id: id, name: "Header")]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomActionPublicConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func secretsCodableRoundTrip() throws {
        let original = CustomActionSecrets(
            url: "https://example.com",
            body: "payload",
            headerValues: ["abc": "xyz"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomActionSecrets.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func disabledSlotIsNeverVisible() {
        let cfg = CustomActionConfig(enabled: false, visibility: .always)
        #expect(!isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: false))
        #expect(!isCustomActionVisible(cfg, isDisconnected: true, isUnconfigured: false))
        #expect(!isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: true))
    }

    @Test
    func alwaysVisibilityIgnoresConnection() {
        let cfg = CustomActionConfig(enabled: true, visibility: .always)
        #expect(isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: false))
        #expect(isCustomActionVisible(cfg, isDisconnected: true, isUnconfigured: false))
        #expect(isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: true))
    }

    @Test
    func whenConnectedHidesWhileDisconnectedOrUnconfigured() {
        let cfg = CustomActionConfig(enabled: true, visibility: .whenConnected)
        #expect(isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: false))
        #expect(!isCustomActionVisible(cfg, isDisconnected: true, isUnconfigured: false))
        #expect(!isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: true))
    }

    @Test
    func whenDisconnectedHidesWhileConnected() {
        let cfg = CustomActionConfig(enabled: true, visibility: .whenDisconnected)
        #expect(!isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: false))
        #expect(isCustomActionVisible(cfg, isDisconnected: true, isUnconfigured: false))
        #expect(isCustomActionVisible(cfg, isDisconnected: false, isUnconfigured: true))
    }

    @Test
    func slotIsHeaderClassification() {
        #expect(CustomActionSlot.headerLeft.isHeader)
        #expect(CustomActionSlot.headerRight.isHeader)
        #expect(!CustomActionSlot.rowLeft.isHeader)
        #expect(!CustomActionSlot.rowRight.isHeader)
        #expect(!CustomActionSlot.rowSecondLeft.isHeader)
        #expect(!CustomActionSlot.rowSecondRight.isHeader)
        #expect(CustomActionSlot.allCases.count == 6)
    }

    @Test
    func isValidRequiresEnabledAndNonEmptyURL() {
        var cfg = CustomActionConfig(enabled: true, url: "")
        #expect(!cfg.isValid)
        cfg.url = "  "
        #expect(!cfg.isValid)
        cfg.url = "https://example.com"
        #expect(cfg.isValid)
        cfg.enabled = false
        #expect(!cfg.isValid)
    }
}
