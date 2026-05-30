#if !PROTOTYPE_MODE
    import Foundation
    import VLCKit

    /// Builds `VLCMedia` for a camera stream with low-latency options. The
    /// option computation is a pure function so the transport/credential
    /// mapping is unit-testable without instantiating libvlc.
    enum VLCMediaFactory {
        /// Default network buffer. Small enough for a near-live preview, large
        /// enough to ride out typical LAN jitter. Tunable per camera.
        static let defaultNetworkCachingMs = 300

        static func makeMedia(
            for request: CameraStreamRequest,
            networkCachingMs: Int = defaultNetworkCachingMs
        ) -> VLCMedia? {
            let media = VLCMedia(url: request.url)
            for option in options(for: request, networkCachingMs: networkCachingMs) {
                media.addOption(option)
            }
            return media
        }

        /// The libvlc per-media options for a request. Pure and deterministic
        /// so `VLCMediaFactoryTests` asserts the mapping for each transport.
        ///
        /// `:rtsp-tcp` replaces the former `#transport=tcp` go2rtc fragment;
        /// `:network-caching` is the key latency knob; `:no-audio` mirrors the
        /// muted AVPlayer. UDP / multicast are libvlc's default negotiation, so
        /// they add no option.
        static func options(
            for request: CameraStreamRequest,
            networkCachingMs: Int = defaultNetworkCachingMs
        ) -> [String] {
            var options: [String] = []
            let scheme = request.url.scheme?.lowercased() ?? ""
            if scheme == "rtsp" || scheme == "rtsps" {
                switch request.transport {
                case .tcp:
                    options.append(":rtsp-tcp")
                case .http:
                    options.append(":rtsp-http")
                case .udp, .udpMulticast:
                    break
                }
            }
            options.append(":network-caching=\(networkCachingMs)")
            options.append(":clock-jitter=0")
            options.append(":clock-synchro=0")
            options.append(":no-audio")
            return options
        }

        /// Player/library-level options (CLI-style `--` flags). This libvlc
        /// build honors the RTSP transport reliably only when set here, not just
        /// per media, so the transport is forced at both levels.
        static func playerOptions(for request: CameraStreamRequest) -> [String] {
            let scheme = request.url.scheme?.lowercased() ?? ""
            guard scheme == "rtsp" || scheme == "rtsps" else { return [] }
            switch request.transport {
            case .tcp:
                return ["--rtsp-tcp"]
            case .http:
                return ["--rtsp-http"]
            case .udp, .udpMulticast:
                return []
            }
        }
    }
#endif
