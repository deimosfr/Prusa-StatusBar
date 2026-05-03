import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer name resolution (override > API
///   name > hostname > literal fallback).
@MainActor
struct AppModelResolvedPrinterNameTests {
    @Test
    func overrideWinsOverApiName() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "core-one.local")
        model.printerNameOverride = "Lab MK4"
        #expect(model.resolvedPrinterName == "Lab MK4")
    }

    @Test
    func apiNameUsedWhenOverrideIsNil() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "core-one.local")
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "core-one.local")
    }

    @Test
    func apiNameUsedWhenOverrideTrimsToEmpty() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "core-one.local")
        model.printerNameOverride = "   "
        #expect(model.resolvedPrinterName == "core-one.local")
    }

    @Test
    func fallbackWhenNeitherSourceHasValue() {
        let model = AppModel()
        model.printerInfo = nil
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "Prusa StatusBar")
    }

    @Test
    func fallbackWhenApiNameAndHostnameAreEmpty() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "", hostname: "")
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "Prusa StatusBar")
    }

    @Test
    func hostnameUsedWhenApiNameIsNil() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: nil, hostname: "prusa-core-one")
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "prusa-core-one")
    }

    @Test
    func hostnameUsedWhenApiNameIsEmpty() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "", hostname: "prusa-core-one")
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "prusa-core-one")
    }

    @Test
    func apiNameWinsOverHostname() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "Workshop MK4", hostname: "prusa-mk4")
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "Workshop MK4")
    }

    // MARK: - 30-char cap (cap-display-name-thirty-chars)

    @Test
    func overrideTruncatedToThirtyCharacters() {
        let model = AppModel()
        let source = String(repeating: "a", count: 35)
        model.printerNameOverride = source
        let resolved = model.resolvedPrinterName
        #expect(resolved.count == 30)
        #expect(resolved == String(source.prefix(30)))
    }

    @Test
    func apiNameTruncatedToThirtyCharacters() {
        let model = AppModel()
        let source = "core-one-very-long-host-name-from-firmware.lan"
        model.printerInfo = PrinterInfo(name: source)
        model.printerNameOverride = nil
        let resolved = model.resolvedPrinterName
        #expect(resolved.count == 30)
        #expect(resolved == String(source.prefix(30)))
    }

    @Test
    func hostnameTruncatedToThirtyCharacters() {
        let model = AppModel()
        let source = String(repeating: "h", count: 40)
        model.printerInfo = PrinterInfo(name: nil, hostname: source)
        model.printerNameOverride = nil
        let resolved = model.resolvedPrinterName
        #expect(resolved.count == 30)
        #expect(resolved == String(source.prefix(30)))
    }

    @Test
    func shortNamesAreNotPadded() {
        let model = AppModel()
        model.printerInfo = PrinterInfo(name: "MK4")
        model.printerNameOverride = nil
        #expect(model.resolvedPrinterName == "MK4")
    }
}
