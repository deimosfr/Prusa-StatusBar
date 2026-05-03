import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer tab edits Generic Camera
///   (scheme allowlist on stream + still URL fields)
struct GenericCameraURLValidatorTests {
    @Test
    func emptyMapsToEmpty() {
        #expect(GenericCameraURLValidator.validate("", field: .stream) == .empty)
        #expect(GenericCameraURLValidator.validate("   ", field: .still) == .empty)
    }

    @Test
    func streamFieldAcceptsRtsp() {
        let result = GenericCameraURLValidator.validate("rtsp://192.168.1.50:554/stream1", field: .stream)
        guard case let .valid(url) = result else {
            Issue.record("expected .valid for rtsp")
            return
        }
        #expect(url.scheme == "rtsp")
        #expect(url.host == "192.168.1.50")
    }

    @Test
    func streamFieldAcceptsRtsps() {
        let result = GenericCameraURLValidator.validate("rtsps://cam.local/stream", field: .stream)
        guard case .valid = result else {
            Issue.record("expected .valid for rtsps")
            return
        }
    }

    @Test
    func streamFieldAcceptsHttpAndHttps() {
        guard case .valid = GenericCameraURLValidator.validate("http://cam.local/mjpg", field: .stream) else {
            Issue.record("expected .valid for http")
            return
        }
        guard case .valid = GenericCameraURLValidator.validate("https://cam.local/mjpg", field: .stream) else {
            Issue.record("expected .valid for https")
            return
        }
    }

    @Test
    func stillFieldRejectsRtsp() {
        #expect(GenericCameraURLValidator.validate("rtsp://cam/snap", field: .still) == .invalid)
    }

    @Test
    func stillFieldAcceptsHttpAndHttps() {
        guard case .valid = GenericCameraURLValidator.validate("http://cam.local/snap.jpg", field: .still) else {
            Issue.record("expected .valid for http still")
            return
        }
        guard case .valid = GenericCameraURLValidator.validate("https://cam.local/snap.jpg", field: .still) else {
            Issue.record("expected .valid for https still")
            return
        }
    }

    @Test
    func disallowedSchemesRejected() {
        #expect(GenericCameraURLValidator.validate("file:///etc/passwd", field: .stream) == .invalid)
        #expect(GenericCameraURLValidator.validate("javascript:alert(1)", field: .stream) == .invalid)
        #expect(GenericCameraURLValidator.validate("data:image/jpeg;base64,abc", field: .still) == .invalid)
    }

    @Test
    func bareHostRejected() {
        #expect(GenericCameraURLValidator.validate("192.168.1.50/stream", field: .stream) == .invalid)
    }
}
