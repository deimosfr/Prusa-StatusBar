#if !PROTOTYPE_MODE
    import AppKit
    import CoreGraphics
    import Foundation
    import ImageIO
    import VLCKit

    /// One-shot still-frame grab from a camera stream. Replaces the go2rtc
    /// `/api/frame.jpeg` + MP4 frame-grab path used for notification snapshots.
    protocol FrameGrabbing: Sendable {
        func grab(request: CameraStreamRequest, timeout: TimeInterval) async throws -> Data
    }

    /// Grabs a single frame from a live stream by spinning up a transient,
    /// off-screen `VLCMediaPlayer` (hosted in an ordered-in off-screen window so
    /// libvlc has a real video output), waiting for the first decoded frame,
    /// then `saveVideoSnapshot`. `VLCMediaThumbnailer` is unsuitable here: it is
    /// built for seekable media and never completes on a live RTSP stream.
    struct VLCSnapshotGrabber: FrameGrabbing {
        enum GrabError: Error, Equatable {
            case mediaBuildFailed
            case timeout
            case encodingFailed
        }

        let networkCachingMs: Int

        init(networkCachingMs: Int = VLCMediaFactory.defaultNetworkCachingMs) {
            self.networkCachingMs = networkCachingMs
        }

        func grab(request: CameraStreamRequest, timeout: TimeInterval) async throws -> Data {
            try await Self.capture(request: request, timeout: timeout, networkCachingMs: networkCachingMs)
        }

        @MainActor
        private static func capture(
            request: CameraStreamRequest,
            timeout: TimeInterval,
            networkCachingMs: Int
        ) async throws -> Data {
            guard let media = VLCMediaFactory.makeMedia(for: request, networkCachingMs: networkCachingMs) else {
                throw GrabError.mediaBuildFailed
            }

            // Off-screen, ordered-in window gives libvlc a real GPU video output
            // without ever being visible to the user.
            let view = VLCVideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
            let window = makeOffscreenVideoWindow(contentView: view)
            window.orderFrontRegardless()

            let player = VLCMediaPlayer()
            player.drawable = view
            player.media = media
            defer {
                player.stop()
                window.orderOut(nil)
                window.close()
            }

            let deadline = Date().addingTimeInterval(timeout)
            player.play()

            // Wait for the first decoded frame (non-zero video size).
            while player.videoSize.width <= 0 || player.videoSize.height <= 0 {
                try Task.checkCancellation()
                guard Date() < deadline else { throw GrabError.timeout }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            // Capture one frame to a temp PNG, then wait for it to be written.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("prusa-snap-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: tmp) }

            // Bound the snapshot to a notification-sized thumbnail: full RTSP
            // resolution (up to 1080p/4K) is wasted on a small attachment and
            // costs memory/CPU/payload. videoSize is non-zero here (wait loop
            // above).
            let snap = snapshotSize(for: player.videoSize)
            player.saveVideoSnapshot(at: tmp.path, withWidth: snap.width, andHeight: snap.height)

            while true {
                try Task.checkCancellation()
                guard Date() < deadline else { throw GrabError.timeout }
                try await Task.sleep(nanoseconds: 100_000_000)
                if let png = try? Data(contentsOf: tmp), png.count > 1000 {
                    return try jpeg(fromPNG: png)
                }
            }
        }

        /// Builds the transient off-screen window that hosts the libvlc video
        /// output. `isReleasedWhenClosed` is forced to `false` because ARC owns
        /// the returned window (the caller holds it in a local): with the AppKit
        /// default of `true`, `close()` would release it a second time and the
        /// resulting over-release crashes on the main-thread autorelease pool
        /// drain. Every other window in the app sets this flag for the same
        /// reason.
        @MainActor
        static func makeOffscreenVideoWindow(contentView: NSView) -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(x: -32000, y: -32000, width: 640, height: 480),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = contentView
            return window
        }

        /// Caps the snapshot's longest edge at `maxEdge` (default 800px),
        /// preserving aspect ratio. Downscales only, never upscales, and never
        /// returns a zero dimension. A non-positive `videoSize` (no decoded
        /// frame yet) falls back to `0, 0`, libvlc's "native resolution" sentinel.
        static func snapshotSize(for videoSize: CGSize, maxEdge: CGFloat = 800) -> (width: Int32, height: Int32) {
            let longest = max(videoSize.width, videoSize.height)
            guard longest > 0 else { return (0, 0) }
            let scale = longest > maxEdge ? maxEdge / longest : 1.0
            let width = Int32(max((videoSize.width * scale).rounded(), 1))
            let height = Int32(max((videoSize.height * scale).rounded(), 1))
            return (width, height)
        }

        /// libvlc writes PNG; re-encode to JPEG to match the notification
        /// attachment contract and keep the payload small.
        private static func jpeg(fromPNG png: Data) throws -> Data {
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let data = CGImageJPEG.data(from: cgImage)
            else {
                throw GrabError.encodingFailed
            }
            return data
        }
    }
#endif
