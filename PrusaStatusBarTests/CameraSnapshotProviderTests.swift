#if !PROTOTYPE_MODE
    import Foundation
    @testable import PrusaStatusBar
    import Testing

    /// Spec coverage:
    /// - `notifications` Requirement: Notifications attach a live camera snapshot
    ///   -- the Buddy and generic-RTSP providers now grab a single frame via the
    ///   injected `FrameGrabbing` (VLC thumbnailer in production), with the Buddy
    ///   path forcing TCP and the generic path honoring its configured transport.
    struct CameraSnapshotProviderTests {
        @Test func buddyProviderGrabsRTSPOverTCP() async throws {
            let fake = FakeFrameGrabber(result: .success(Data([0x01, 0x02, 0x03])))
            let provider = BuddyCameraSnapshotProvider(
                rtspURL: "rtsp://192.168.94.109:554/live/",
                grabber: fake
            )

            let data = try await provider.snapshot(timeout: 5)

            #expect(data == Data([0x01, 0x02, 0x03]))
            #expect(fake.lastRequest?.url.absoluteString == "rtsp://192.168.94.109:554/live/")
            #expect(fake.lastRequest?.transport == .tcp)
        }

        @Test func genericRTSPProviderUsesConfiguredTransport() async throws {
            let fake = FakeFrameGrabber(result: .success(Data([0xAA])))
            let config = GenericCameraConfig(
                enabled: true,
                streamURL: "rtsp://cam.local:554/stream",
                rtspTransport: .udp
            )
            let provider = GenericCameraSnapshotProvider(config: config, grabber: fake)

            let data = try await provider.snapshot(timeout: 5)

            #expect(data == Data([0xAA]))
            #expect(fake.lastRequest?.transport == .udp)
        }

        @Test func genericProviderPrefersStillURLOverGrabber() async {
            // A still URL short-circuits before the stream grabber is consulted.
            let fake = FakeFrameGrabber(result: .failure(StubError.shouldNotBeCalled))
            let config = GenericCameraConfig(
                enabled: true,
                streamURL: "rtsp://cam.local:554/stream",
                stillImageURL: "http://cam.local/snap.jpg",
                rtspTransport: .tcp
            )
            let provider = GenericCameraSnapshotProvider(config: config, grabber: fake)

            // The still path uses URLSession (no network here), so we only assert
            // the grabber was never reached when a still URL is configured.
            _ = try? await provider.snapshot(timeout: 1)
            #expect(fake.lastRequest == nil)
        }
    }

    private enum StubError: Error { case shouldNotBeCalled }

    private final class FakeFrameGrabber: FrameGrabbing, @unchecked Sendable {
        enum Outcome { case success(Data); case failure(Error) }
        let result: Outcome
        private(set) var lastRequest: CameraStreamRequest?

        init(result: Outcome) {
            self.result = result
        }

        func grab(request: CameraStreamRequest, timeout _: TimeInterval) async throws -> Data {
            lastRequest = request
            switch result {
            case let .success(data): return data
            case let .failure(error): throw error
            }
        }
    }
#endif
