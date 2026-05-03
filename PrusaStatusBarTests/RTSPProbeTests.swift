import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` (rtsp-camera-link delta) scenarios "Test camera success"
///   and "Test camera failure". The stub probe lets us exercise the result
///   surface without hitting the network; the live probe is exercised by
///   manual smoke tests against a real camera.
struct RTSPProbeTests {
    @Test
    func stubReturnsSuccess() async {
        let probe = StubRTSPProbe(stubResult: .success(
            RTSPDescribeInfo(sessionDescription: "Buddy Camera", mediaLines: ["video 0 RTP/AVP 96"])
        ))
        let result = await probe.describe(host: "192.168.1.10")
        switch result {
        case let .success(info):
            #expect(info.sessionDescription == "Buddy Camera")
            #expect(info.mediaLines == ["video 0 RTP/AVP 96"])
        case .failure:
            Issue.record("expected success")
        }
    }

    @Test
    func stubReturnsTimeout() async {
        let probe = StubRTSPProbe(stubResult: .failure(.timeout))
        let result = await probe.describe(host: "192.168.1.10")
        if case .failure(.timeout) = result {
            // ok
        } else {
            Issue.record("expected timeout")
        }
    }

    @Test
    func stubReturnsStatus() async {
        let probe = StubRTSPProbe(stubResult: .failure(.status(code: 401, reason: "Unauthorized")))
        let result = await probe.describe(host: "192.168.1.10")
        if case let .failure(.status(code, reason)) = result {
            #expect(code == 401)
            #expect(reason == "Unauthorized")
        } else {
            Issue.record("expected status failure")
        }
    }
}
