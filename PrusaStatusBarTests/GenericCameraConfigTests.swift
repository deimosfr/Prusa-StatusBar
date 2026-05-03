import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Printer tab edits Generic Camera
///   (resolved URL injection: credentials + rtsp_transport)
/// - `menu-bar-ui` Requirement: Dropdown embeds Generic Camera tile
///   (preferredMode resolution, hasUsableSource)
struct GenericCameraConfigTests {
    @Test
    func preferredModeIsNoneWithBothEmpty() {
        let config = GenericCameraConfig(enabled: true)
        #expect(config.preferredMode == .none)
        #expect(!config.hasUsableSource)
    }

    @Test
    func preferredModeIsStreamWhenStreamSet() {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "rtsp://cam.local/s",
            stillImageURL: "https://cam.local/snap.jpg"
        )
        guard case .stream = config.preferredMode else {
            Issue.record("expected .stream")
            return
        }
        #expect(config.hasUsableSource)
    }

    @Test
    func preferredModeIsStillWhenOnlyStillSet() {
        let config = GenericCameraConfig(
            enabled: true,
            stillImageURL: "https://cam.local/snap.jpg"
        )
        guard case .still = config.preferredMode else {
            Issue.record("expected .still")
            return
        }
    }

    @Test
    func preferredModeIsNoneWhenStreamInvalid() {
        let config = GenericCameraConfig(enabled: true, streamURL: "file:///bad")
        #expect(config.preferredMode == .none)
    }

    @Test
    func resolvedStreamURLInjectsBasicCredentials() throws {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "rtsp://192.168.1.50:554/stream1",
            authMode: .basic,
            username: "admin",
            password: "s3cret"
        )
        let url = try #require(config.resolvedStreamURL())
        #expect(url.user == "admin")
        #expect(url.password == "s3cret")
        #expect(url.host == "192.168.1.50")
        #expect(url.port == 554)
    }

    @Test
    func resolvedStreamURLOmitsCredentialsWhenAuthNone() throws {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "rtsp://cam/s",
            authMode: .none,
            username: "admin",
            password: "secret"
        )
        let url = try #require(config.resolvedStreamURL())
        #expect(url.user == nil)
        #expect(url.password == nil)
    }

    @Test
    func resolvedStreamURLAppendsRTSPTransportWhenNonDefault() throws {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "rtsp://cam/s",
            rtspTransport: .udp
        )
        let url = try #require(config.resolvedStreamURL())
        #expect(url.absoluteString.contains("rtsp_transport=udp"))
    }

    @Test
    func resolvedStreamURLOmitsRTSPTransportForTCP() throws {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "rtsp://cam/s",
            rtspTransport: .tcp
        )
        let url = try #require(config.resolvedStreamURL())
        #expect(!url.absoluteString.contains("rtsp_transport"))
    }

    @Test
    func resolvedStreamURLOmitsRTSPTransportForHTTPSource() throws {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "http://cam/mjpg",
            rtspTransport: .udp
        )
        let url = try #require(config.resolvedStreamURL())
        #expect(!url.absoluteString.contains("rtsp_transport"))
    }

    @Test
    func resolvedStillImageURLValidatesHTTPS() throws {
        let config = GenericCameraConfig(
            enabled: true,
            stillImageURL: "https://cam.local/snap.jpg"
        )
        let url = try #require(config.resolvedStillImageURL())
        #expect(url.scheme == "https")
    }

    @Test
    func resolvedStillImageURLRejectsRTSPSource() {
        let config = GenericCameraConfig(
            enabled: true,
            stillImageURL: "rtsp://cam/s"
        )
        #expect(config.resolvedStillImageURL() == nil)
    }

    @Test
    func resolvedStreamURLPercentEncodesCredentials() throws {
        let config = GenericCameraConfig(
            enabled: true,
            streamURL: "rtsp://cam/s",
            authMode: .basic,
            username: "user@x",
            password: "p ss/word"
        )
        let url = try #require(config.resolvedStreamURL())
        let s = url.absoluteString
        #expect(s.contains("user%40x"))
        #expect(s.contains("p%20ss%2Fword") || s.contains("p%20ss%252Fword"))
    }
}
