#if !PROTOTYPE_MODE
    import AppKit
    import SwiftUI
    import VLCKit

    /// Embedded camera preview used by both `CameraTile` (Buddy) and
    /// `GenericCameraTile`. libvlc decodes the camera's RTSP/HTTP stream
    /// directly in-process and renders it into a `VLCVideoView`, so there is no
    /// transmux helper, no localhost server, and no child process. Production
    /// and prototype builds share the SwiftUI surface; prototype renders a
    /// static placeholder (this whole file is excluded from prototype builds).
    ///
    /// The view keeps the same callback contract the AVPlayer version exposed:
    /// `onReady` (first decoded frame), `onPresentationSize` (native video
    /// size, for aspect locking), and `onFailureExhausted` (the reconnect
    /// budget ran out without playback, used to fall back to still images).
    struct CameraPlayerView: NSViewRepresentable {
        let request: CameraStreamRequest
        let onFailureExhausted: (() -> Void)?
        let onReady: (() -> Void)?
        let onPresentationSize: ((CGSize) -> Void)?

        init(
            request: CameraStreamRequest,
            onFailureExhausted: (() -> Void)? = nil,
            onReady: (() -> Void)? = nil,
            onPresentationSize: ((CGSize) -> Void)? = nil
        ) {
            self.request = request
            self.onFailureExhausted = onFailureExhausted
            self.onReady = onReady
            self.onPresentationSize = onPresentationSize
        }

        func makeNSView(context _: Context) -> VLCPlayerNSView {
            let view = VLCPlayerNSView()
            view.failureExhaustedHandler = onFailureExhausted
            view.readyHandler = onReady
            view.presentationSizeHandler = onPresentationSize
            view.load(request: request)
            return view
        }

        func updateNSView(_ nsView: VLCPlayerNSView, context _: Context) {
            nsView.failureExhaustedHandler = onFailureExhausted
            nsView.readyHandler = onReady
            nsView.presentationSizeHandler = onPresentationSize
            nsView.load(request: request)
        }

        static func dismantleNSView(_ nsView: VLCPlayerNSView, coordinator _: ()) {
            nsView.tearDown()
        }
    }

    final class VLCPlayerNSView: NSView, VLCMediaPlayerDelegate {
        private let videoView = VLCVideoView()
        private var player: VLCMediaPlayer?
        private var loadedRequest: CameraStreamRequest?
        private var retry = StreamRetryPolicy()
        private var pendingRetry: Task<Void, Never>?
        private var readyWatch: Task<Void, Never>?
        private var hasReportedReady = false
        private var lastReportedSize: CGSize = .zero

        /// Invoked once the reconnect budget exhausts without a first frame.
        /// `GenericCameraTile` uses it to fall back to still-image polling.
        var failureExhaustedHandler: (() -> Void)?
        /// Invoked the first time a frame is decoded (non-zero video size).
        /// Tiles use it to hide the loading spinner. Kept sticky caller-side.
        var readyHandler: (() -> Void)?
        /// Invoked with the native video size once known, and again if it
        /// changes. Tiles lock their aspect ratio to it so there are no bars.
        var presentationSizeHandler: ((CGSize) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            videoView.frame = bounds
            videoView.autoresizingMask = [.width, .height]
            // Preserve aspect inside the view; the tile sizes itself to the
            // reported video aspect so no letterbox/pillarbox bars appear.
            videoView.fillScreen = false
            addSubview(videoView)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is unsupported")
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        /// libvlc's video output binds to the view's window-backed layer. When
        /// the view is hosted in an `NSPopover`, SwiftUI mounts this view (and
        /// the old code started playback) before the popover attaches it to its
        /// transient window, so the vout latched onto a surface the popover then
        /// invalidated: one decoded frame flashed, then the tile went black for
        /// good. A stable `NSWindow` (the detached / Quick Look popup) never had
        /// that gap, which is why windowed playback worked. We therefore drive
        /// the actual start from here, once the view is in its final window, and
        /// rebuild against whatever window it lands in.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let request = loadedRequest else { return }
            if window != nil {
                installPlayer(request: request)
            } else {
                // Left its window (popover closing or re-parenting): stop
                // upstream so libvlc is not decoding into a dead surface.
                // Re-entering a window reinstalls; SwiftUI dismantle still
                // routes teardown through `tearDown`.
                stopPlayback()
            }
        }

        func load(request: CameraStreamRequest) {
            guard request != loadedRequest else { return }
            loadedRequest = request
            retry.reset()
            hasReportedReady = false
            lastReportedSize = .zero
            // Only start if we are already in a window; otherwise defer to
            // `viewDidMoveToWindow` so the vout binds to a live surface.
            if window != nil {
                installPlayer(request: request)
            }
        }

        func tearDown() {
            ActiveCameraPlayers.shared.deregister(ObjectIdentifier(self))
            pendingRetry?.cancel()
            pendingRetry = nil
            readyWatch?.cancel()
            readyWatch = nil
            teardownPlayer()
            loadedRequest = nil
            hasReportedReady = false
            lastReportedSize = .zero
            failureExhaustedHandler = nil
            readyHandler = nil
            presentationSizeHandler = nil
        }

        private func teardownPlayer() {
            player?.delegate = nil
            player?.stop()
            player?.drawable = nil
            player = nil
        }

        private func installPlayer(request: CameraStreamRequest) {
            readyWatch?.cancel()
            teardownPlayer()
            guard let media = VLCMediaFactory.makeMedia(for: request) else {
                scheduleRetry()
                return
            }
            let player = VLCMediaPlayer(options: VLCMediaFactory.playerOptions(for: request))
            player.drawable = videoView
            player.delegate = self
            player.media = media
            self.player = player
            ActiveCameraPlayers.shared.register(ObjectIdentifier(self)) { [weak self] in
                self?.stopPlayback()
            }
            player.play()
            if !hasReportedReady {
                startReadyWatch()
            }
        }

        /// Stops upstream playback without tearing the view down. Called by the
        /// keepalive registry; the SwiftUI dismantle path calls `tearDown`.
        private func stopPlayback() {
            pendingRetry?.cancel()
            pendingRetry = nil
            readyWatch?.cancel()
            readyWatch = nil
            player?.stop()
        }

        // MARK: - VLCMediaPlayerDelegate (called on a libvlc thread)

        nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
            let state = (aNotification.object as? VLCMediaPlayer)?.state ?? .error
            Task { @MainActor [weak self] in
                self?.handle(state: state)
            }
        }

        private func handle(state: VLCMediaPlayerState) {
            switch state {
            case .playing, .esAdded:
                retry.reset()
                pendingRetry?.cancel()
                pendingRetry = nil
                checkReady()
            case .error, .ended:
                // .stopped is intentional (teardown / keepalive) so it is not
                // treated as a failure; only real errors and unexpected ends
                // trigger a reconnect.
                scheduleRetry()
            default:
                break
            }
        }

        private func checkReady() {
            guard let player else { return }
            let size = player.videoSize
            guard size.width > 0, size.height > 0 else { return }
            reportSize(size)
            if !hasReportedReady {
                hasReportedReady = true
                readyHandler?()
            }
            // A frame is showing: cancel any scheduled reconnect so a pending
            // retry does not tear the playing stream down (which caused the
            // video to flash then go black).
            pendingRetry?.cancel()
            pendingRetry = nil
            readyWatch?.cancel()
            readyWatch = nil
        }

        private func reportSize(_ size: CGSize) {
            guard size.width > 0, size.height > 0, size != lastReportedSize else { return }
            lastReportedSize = size
            presentationSizeHandler?(size)
        }

        /// Polls `videoSize` until the first frame is decoded (VLCKit 3.x has no
        /// size-changed delegate). Keeps polling as long as the player stays
        /// connected: this camera's keyframe interval is long, and forcing a
        /// reconnect early does not help (it will not accept a quick re-SETUP and
        /// the stream churns). A genuine failure arrives as a `.error` / `.ended`
        /// state and is handled separately by `scheduleRetry`.
        private func startReadyWatch() {
            readyWatch?.cancel()
            readyWatch = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard let self, !Task.isCancelled else { return }
                    checkReady()
                    if hasReportedReady {
                        return
                    }
                }
            }
        }

        private func scheduleRetry() {
            guard let request = loadedRequest else { return }
            let delay = retry.nextDelay { [weak self] in
                guard let self, !hasReportedReady else { return }
                failureExhaustedHandler?()
            }
            pendingRetry?.cancel()
            pendingRetry = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled, loadedRequest == request else { return }
                installPlayer(request: request)
            }
        }
    }
#endif
