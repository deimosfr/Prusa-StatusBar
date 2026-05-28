import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer tab validates fields live as the user types
///   (PrusaLink URL + fallback URL rules)
struct PrinterBaseURLValidatorTests {
    @Test
    func emptyAndWhitespaceMapToEmpty() {
        #expect(PrinterBaseURLValidator.validate("") == .empty)
        #expect(PrinterBaseURLValidator.validate("   ") == .empty)
        #expect(PrinterBaseURLValidator.validate("\t\n") == .empty)
    }

    @Test
    func acceptsHttpAndHttps() {
        guard case let .valid(httpURL) = PrinterBaseURLValidator.validate("http://printer.lan") else {
            Issue.record("expected .valid for http")
            return
        }
        #expect(httpURL.scheme == "http")
        #expect(httpURL.host == "printer.lan")

        guard case let .valid(httpsURL) = PrinterBaseURLValidator.validate("https://printer.lan") else {
            Issue.record("expected .valid for https")
            return
        }
        #expect(httpsURL.scheme == "https")
    }

    @Test
    func acceptsUppercaseScheme() {
        guard case .valid = PrinterBaseURLValidator.validate("HTTP://printer.lan") else {
            Issue.record("expected .valid for uppercase scheme")
            return
        }
    }

    @Test
    func acceptsPortAndPath() {
        guard case let .valid(url) = PrinterBaseURLValidator.validate("http://printer.lan:8080/api") else {
            Issue.record("expected .valid for url with port and path")
            return
        }
        #expect(url.port == 8080)
    }

    @Test
    func rejectsMissingScheme() {
        #expect(PrinterBaseURLValidator.validate("printer.lan") == .invalid)
        #expect(PrinterBaseURLValidator.validate("printer.lan/api") == .invalid)
    }

    @Test
    func rejectsDisallowedSchemes() {
        #expect(PrinterBaseURLValidator.validate("ftp://printer.lan") == .invalid)
        #expect(PrinterBaseURLValidator.validate("file:///etc/hosts") == .invalid)
        #expect(PrinterBaseURLValidator.validate("javascript:alert(1)") == .invalid)
        #expect(PrinterBaseURLValidator.validate("rtsp://printer.lan/live") == .invalid)
    }

    @Test
    func rejectsMissingHost() {
        #expect(PrinterBaseURLValidator.validate("http://") == .invalid)
        #expect(PrinterBaseURLValidator.validate("http:///path") == .invalid)
    }

    @Test
    func rejectsGarbage() {
        #expect(PrinterBaseURLValidator.validate("not a url") == .invalid)
        #expect(PrinterBaseURLValidator.validate("http:// space") == .invalid)
    }

    @Test
    func trimsWhitespaceBeforeValidating() {
        guard case .valid = PrinterBaseURLValidator.validate("  http://printer.lan  ") else {
            Issue.record("expected .valid after trim")
            return
        }
    }

    @Test
    func acceptsValidIPv4Literal() {
        guard case .valid = PrinterBaseURLValidator.validate("http://192.168.1.42") else {
            Issue.record("expected .valid for 192.168.1.42")
            return
        }
    }

    @Test
    func rejectsIPv4WithOctetOver255() {
        #expect(PrinterBaseURLValidator.validate("http://192.168.94.1312") == .invalid)
        #expect(PrinterBaseURLValidator.validate("http://256.0.0.1") == .invalid)
        #expect(PrinterBaseURLValidator.validate("http://1.2.3.999/path") == .invalid)
    }

    @Test
    func acceptsValidIPv6Literal() {
        guard case .valid = PrinterBaseURLValidator.validate("http://[::1]/api") else {
            Issue.record("expected .valid for [::1]")
            return
        }
        guard case .valid = PrinterBaseURLValidator.validate("http://[2001:db8::1]") else {
            Issue.record("expected .valid for [2001:db8::1]")
            return
        }
    }

    @Test
    func rejectsMalformedIPv6Literal() {
        #expect(PrinterBaseURLValidator.validate("http://[::g]") == .invalid)
    }
}
