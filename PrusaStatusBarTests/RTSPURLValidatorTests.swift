import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer tab edits optional RTSP camera URL
/// - `menu-bar-ui` Requirement: Dropdown LinksRow shows a Camera button
///   when RTSP URL is set (re-validation in the click handler)
struct RTSPURLValidatorTests {
    @Test
    func emptyInputMapsToEmpty() {
        #expect(RTSPURLValidator.validate("") == .empty)
        #expect(RTSPURLValidator.validate("   ") == .empty)
    }

    @Test
    func validRtspSchemeReturnsValid() {
        let result = RTSPURLValidator.validate("rtsp://192.168.94.109:554/live/")
        guard case let .valid(url) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(url.scheme == "rtsp")
        #expect(url.host == "192.168.94.109")
        #expect(url.port == 554)
    }

    @Test
    func validRtspsSchemeReturnsValid() {
        let result = RTSPURLValidator.validate("rtsps://cam.local/stream")
        guard case .valid = result else {
            Issue.record("expected .valid for rtsps URL")
            return
        }
    }

    @Test
    func schemeIsCaseInsensitive() {
        let result = RTSPURLValidator.validate("RTSP://cam.local/stream")
        guard case .valid = result else {
            Issue.record("expected .valid for upper-case scheme")
            return
        }
    }

    @Test
    func surroundingWhitespaceIsTrimmed() {
        let result = RTSPURLValidator.validate("  rtsp://cam.local/  ")
        guard case let .valid(url) = result else {
            Issue.record("expected .valid after trimming")
            return
        }
        #expect(url.scheme == "rtsp")
    }

    @Test
    func httpSchemeIsInvalid() {
        #expect(RTSPURLValidator.validate("http://cam.local/stream") == .invalid)
    }

    @Test
    func bareHostIsInvalid() {
        #expect(RTSPURLValidator.validate("192.168.94.109:554/live/") == .invalid)
    }
}
