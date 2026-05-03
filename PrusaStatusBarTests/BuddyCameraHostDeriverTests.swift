import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` (rtsp-camera-link delta) Requirement: Printer tab edits
///   Buddy Camera host. The deriver is the pure-data half of that
///   requirement; UI behaviour rides on top.
struct BuddyCameraHostDeriverTests {
    @Test
    func ipHostDerivesCanonicalURL() throws {
        let result = BuddyCameraHostDeriver.rtspURL(forHost: "192.168.94.109")
        #expect(try result == .success(#require(URL(string: "rtsp://192.168.94.109:554/live/"))))
    }

    @Test
    func dnsHostDerivesCanonicalURL() throws {
        let result = BuddyCameraHostDeriver.rtspURL(forHost: "printer-cam.lan")
        #expect(try result == .success(#require(URL(string: "rtsp://printer-cam.lan:554/live/"))))
    }

    @Test
    func surroundingWhitespaceIsTrimmed() throws {
        let result = BuddyCameraHostDeriver.rtspURL(forHost: "  10.0.0.5  ")
        #expect(try result == .success(#require(URL(string: "rtsp://10.0.0.5:554/live/"))))
    }

    @Test
    func emptyHostFails() {
        #expect(BuddyCameraHostDeriver.rtspURL(forHost: "") == .failure(.empty))
        #expect(BuddyCameraHostDeriver.rtspURL(forHost: "   ") == .failure(.empty))
    }

    @Test
    func hostWithSchemeIsRejected() {
        let result = BuddyCameraHostDeriver.rtspURL(forHost: "rtsp://192.168.1.10")
        #expect(result == .failure(.containsSchemeOrPort))
    }

    @Test
    func hostWithExplicitPortIsRejected() {
        let result = BuddyCameraHostDeriver.rtspURL(forHost: "192.168.1.10:8554")
        #expect(result == .failure(.containsSchemeOrPort))
    }

    @Test
    func inverseExtractsHost() {
        let host = BuddyCameraHostDeriver.host(fromRTSPURL: "rtsp://192.168.94.109:554/live/")
        #expect(host == "192.168.94.109")
    }

    @Test
    func inverseReturnsNilForEmpty() {
        #expect(BuddyCameraHostDeriver.host(fromRTSPURL: "") == nil)
        #expect(BuddyCameraHostDeriver.host(fromRTSPURL: "   ") == nil)
    }

    @Test
    func inverseReturnsNilForUnparseableInput() {
        #expect(BuddyCameraHostDeriver.host(fromRTSPURL: "not-a-url") == nil)
    }
}
