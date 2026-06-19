#if !PROTOTYPE_MODE
    import Foundation
    @testable import PrusaStatusBar
    import Testing

    /// Spec coverage:
    /// - `menu-bar-ui` Requirement: Dropdown embeds live RTSP video when configured
    ///   (transport: Buddy forces TCP)
    /// - `menu-bar-ui` Requirement: Dropdown embeds Generic Camera tile beneath
    ///   Buddy tile (RTSP transport mapping)
    ///
    /// Pure mapping from a `CameraStreamRequest` to libvlc media options, the
    /// VLC replacement for the former go2rtc `#transport=` / `?rtsp_transport=`
    /// handling. No libvlc instance is created.
    struct VLCMediaFactoryTests {
        private func options(
            _ urlString: String,
            _ transport: GenericCameraRTSPTransport,
            caching: Int = 300
        ) throws -> [String] {
            let url = try #require(URL(string: urlString))
            return VLCMediaFactory.options(
                for: CameraStreamRequest(url: url, transport: transport),
                networkCachingMs: caching
            )
        }

        @Test func rtspTCPForcesTCPTransport() throws {
            let opts = try options("rtsp://cam.local:554/live/", .tcp)
            #expect(opts.contains(":rtsp-tcp"))
            #expect(!opts.contains(":rtsp-http"))
        }

        @Test func rtspHTTPTransport() throws {
            let opts = try options("rtsp://cam.local:554/live/", .http)
            #expect(opts.contains(":rtsp-http"))
            #expect(!opts.contains(":rtsp-tcp"))
        }

        @Test func rtspUDPLeavesTransportToLibvlc() throws {
            let opts = try options("rtsp://cam.local:554/live/", .udp)
            #expect(!opts.contains(":rtsp-tcp"))
            #expect(!opts.contains(":rtsp-http"))
        }

        @Test func rtspMulticastLeavesTransportToLibvlc() throws {
            let opts = try options("rtsp://cam.local:554/live/", .udpMulticast)
            #expect(!opts.contains(":rtsp-tcp"))
            #expect(!opts.contains(":rtsp-http"))
        }

        @Test func httpStreamGetsNoRTSPTransportOption() throws {
            // Generic HTTP/MJPEG stream: RTSP transport options must not apply.
            let opts = try options("http://cam.local:8080/stream", .tcp)
            #expect(!opts.contains(":rtsp-tcp"))
        }

        @Test func lowLatencyOptionsAlwaysPresent() throws {
            let opts = try options("rtsp://cam.local:554/live/", .tcp)
            #expect(opts.contains(":network-caching=300"))
            #expect(opts.contains(":clock-jitter=0"))
            #expect(opts.contains(":no-audio"))
        }

        @Test func networkCachingIsConfigurable() throws {
            let opts = try options("rtsp://cam.local/s", .tcp, caching: 150)
            #expect(opts.contains(":network-caching=150"))
            #expect(!opts.contains(":network-caching=300"))
        }

        @Test func makeMediaPreservesCredentialsInURL() throws {
            let url = try #require(URL(string: "rtsp://user:pass@cam.local/live"))
            let media = VLCMediaFactory.makeMedia(for: CameraStreamRequest(url: url, transport: .tcp))
            #expect(media != nil)
            #expect(media?.url == url)
        }

        @Test func playerOptionsForceTransportForRTSPOnly() throws {
            let rtsp = try #require(URL(string: "rtsp://cam.local/live"))
            func opts(_ transport: GenericCameraRTSPTransport) -> [String] {
                VLCMediaFactory.playerOptions(for: CameraStreamRequest(url: rtsp, transport: transport))
            }
            #expect(opts(.tcp) == ["--rtsp-tcp"])
            #expect(opts(.http) == ["--rtsp-http"])
            #expect(opts(.udp).isEmpty)
            // Non-RTSP (HTTP/MJPEG) streams get no transport flag.
            let http = try #require(URL(string: "http://cam.local/stream"))
            #expect(VLCMediaFactory.playerOptions(for: CameraStreamRequest(url: http, transport: .tcp)).isEmpty)
        }
    }
#endif
