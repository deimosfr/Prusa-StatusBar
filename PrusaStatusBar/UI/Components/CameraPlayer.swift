#if !PROTOTYPE_MODE
    import AVFoundation
    import AVKit
    import SwiftUI

    /// Thin AVPlayerLayer-backed view used by both `CameraTile` (Buddy) and
    /// `GenericCameraTile`. AVKit's stock `VideoPlayer` adds a playback
    /// chrome row we don't want for a status-bar tile, so we drop to
    /// `AVPlayerLayer` and render the bare video.
    ///
    /// Lifecycle: `makeNSView` and `updateNSView` load the URL into the
    /// underlying `PlayerNSView`. `dismantleNSView` tears down the player
    /// (pause + clear) so SwiftUI removing the view from the hierarchy
    /// stops upstream traffic immediately.
    struct CameraPlayerView: NSViewRepresentable {
        let url: URL
        let onFailureExhausted: (() -> Void)?
        let onReady: (() -> Void)?
        let onPresentationSize: ((CGSize) -> Void)?

        init(
            url: URL,
            onFailureExhausted: (() -> Void)? = nil,
            onReady: (() -> Void)? = nil,
            onPresentationSize: ((CGSize) -> Void)? = nil
        ) {
            self.url = url
            self.onFailureExhausted = onFailureExhausted
            self.onReady = onReady
            self.onPresentationSize = onPresentationSize
        }

        func makeNSView(context _: Context) -> PlayerNSView {
            let view = PlayerNSView()
            view.failureExhaustedHandler = onFailureExhausted
            view.readyHandler = onReady
            view.presentationSizeHandler = onPresentationSize
            view.load(url: url)
            return view
        }

        func updateNSView(_ nsView: PlayerNSView, context _: Context) {
            nsView.failureExhaustedHandler = onFailureExhausted
            nsView.readyHandler = onReady
            nsView.presentationSizeHandler = onPresentationSize
            nsView.load(url: url)
        }

        static func dismantleNSView(_ nsView: PlayerNSView, coordinator _: ()) {
            nsView.tearDown()
        }
    }

    final class PlayerNSView: NSView {
        private let playerLayer = AVPlayerLayer()
        private var player: AVPlayer?
        private var loadedURL: URL?
        private var statusObservation: NSKeyValueObservation?
        private var presentationSizeObservation: NSKeyValueObservation?
        private var lastReportedPresentationSize: CGSize = .zero
        private var retryAttempt: Int = 0
        private var pendingRetry: Task<Void, Never>?

        /// Invoked once the retry budget exhausts without `.readyToPlay`.
        /// Used by `GenericCameraTile` to fall back to still-image polling.
        var failureExhaustedHandler: (() -> Void)?

        /// Invoked the first time the underlying `AVPlayerItem` flips to
        /// `.readyToPlay`. Tiles use it to hide their loading spinner and
        /// expand to the real video height. Kept sticky on the caller side
        /// so transient stalls do not flap the spinner back on.
        var readyHandler: (() -> Void)?

        /// Invoked when the underlying `AVPlayerItem` reports a non-zero
        /// `presentationSize`, and again if that size changes. Tiles use it
        /// to lock their aspect ratio to the actual video so AVPlayerLayer
        /// does not add letterbox/pillarbox bars.
        var presentationSizeHandler: ((CGSize) -> Void)?

        /// go2rtc is started on demand in the same runloop tick the popover
        /// opens, but its HTTP API takes a few hundred ms to a couple of
        /// seconds before the m3u8 endpoint serves a parseable playlist. If
        /// AVPlayer hits it during that window the AVPlayerItem flips to
        /// .failed and never retries on its own, leaving a dark tile. We
        /// re-attempt with linear backoff up to a short cap.
        ///
        /// Extended to cover cameras with slow RTSP keyframe intervals: go2rtc
        /// needs at least one keyframe before generating the first HLS segment.
        /// With a 2-5s keyframe interval plus RTSP connection time, the
        /// original 8.1s budget was too tight. 23s covers most real cameras.
        private let retryBackoffs: [TimeInterval] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0]

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is unsupported")
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        func load(url: URL) {
            guard url != loadedURL else { return }
            loadedURL = url
            retryAttempt = 0
            installPlayer(url: url)
        }

        func tearDown() {
            pendingRetry?.cancel()
            pendingRetry = nil
            statusObservation?.invalidate()
            statusObservation = nil
            presentationSizeObservation?.invalidate()
            presentationSizeObservation = nil
            lastReportedPresentationSize = .zero
            player?.pause()
            playerLayer.player = nil
            player = nil
            loadedURL = nil
            retryAttempt = 0
            failureExhaustedHandler = nil
            readyHandler = nil
            presentationSizeHandler = nil
        }

        private func installPlayer(url: URL) {
            statusObservation?.invalidate()
            statusObservation = nil
            presentationSizeObservation?.invalidate()
            presentationSizeObservation = nil
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            // Keep playback live: if the HLS stream momentarily stalls
            // (e.g. go2rtc is still warming up), let AVPlayer wait rather
            // than freezing on the first decoded frame.
            player.automaticallyWaitsToMinimizeStalling = true
            playerLayer.player = player
            self.player = player

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let status = item.status
                let errorMessage = item.error?.localizedDescription
                Task { @MainActor in
                    self?.handle(itemStatus: status, errorMessage: errorMessage)
                }
            }

            let opts: NSKeyValueObservingOptions = [.new, .initial]
            presentationSizeObservation = item.observe(\.presentationSize, options: opts) { [weak self] item, _ in
                let size = item.presentationSize
                Task { @MainActor in
                    self?.handle(presentationSize: size)
                }
            }

            player.play()
        }

        private func handle(presentationSize: CGSize) {
            guard presentationSize.width > 0, presentationSize.height > 0 else { return }
            if presentationSize == lastReportedPresentationSize { return }
            lastReportedPresentationSize = presentationSize
            presentationSizeHandler?(presentationSize)
        }

        private func handle(itemStatus: AVPlayerItem.Status, errorMessage _: String?) {
            switch itemStatus {
            case .readyToPlay:
                retryAttempt = 0
                pendingRetry?.cancel()
                pendingRetry = nil
                readyHandler?()
            case .failed:
                scheduleRetry()
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        private func scheduleRetry() {
            guard let url = loadedURL else { return }
            let delay: TimeInterval
            if retryAttempt < retryBackoffs.count {
                delay = retryBackoffs[retryAttempt]
                retryAttempt += 1
            } else {
                // Fast budget exhausted. Notify the fallback handler exactly
                // once, then switch to a slow 10s periodic retry so the tile
                // self-heals when go2rtc eventually delivers the stream
                // (e.g. camera with a very long keyframe interval).
                // tearDown() cancels pendingRetry, so retries stop on close.
                if retryAttempt == retryBackoffs.count {
                    failureExhaustedHandler?()
                    retryAttempt += 1
                }
                delay = 10.0
            }
            pendingRetry?.cancel()
            pendingRetry = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled, loadedURL == url else { return }
                installPlayer(url: url)
            }
        }
    }
#endif
