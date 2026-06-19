#if !PROTOTYPE_MODE
    import Foundation

    /// Captures a single still image from one specific camera source. Opaque to
    /// the orchestrator (`CameraSnapshotService`) so each source chooses its own
    /// transport: a one-shot libvlc frame grab for RTSP, a plain HTTP GET for a
    /// still URL, or an MJPEG one-frame grab for an HTTP stream URL.
    protocol CameraSnapshotProvider: Sendable {
        func snapshot(timeout: TimeInterval) async throws -> Data
    }

    enum CameraSnapshotError: Error, Equatable {
        case noSource
        case unsupportedScheme(String)
        case badStatus(Int)
    }

    /// Buddy built-in camera (RTSP). Grabs one decoded frame directly via
    /// libvlc (`VLCSnapshotGrabber`); there is no helper to spin up or tear
    /// down, so the grab owns its own short-lived libvlc instance.
    struct BuddyCameraSnapshotProvider: CameraSnapshotProvider {
        let rtspURL: String
        var grabber: any FrameGrabbing = VLCSnapshotGrabber()

        func snapshot(timeout: TimeInterval) async throws -> Data {
            guard let url = URL(string: rtspURL) else { throw CameraSnapshotError.noSource }
            Log.cameraSnapshot.info("Buddy snapshot start; t=\(timeout, privacy: .public)s")
            let data = try await grabber.grab(
                request: CameraStreamRequest(url: url, transport: .tcp),
                timeout: timeout
            )
            Log.cameraSnapshot.info("Buddy snapshot ok; bytes=\(data.count, privacy: .public)")
            return data
        }
    }

    /// Generic (user-configured) camera. Tries in order:
    ///
    /// 1. Configured still-image URL: single HTTP GET, returns the body bytes
    ///    as the image. Fastest path because nothing is decoded.
    /// 2. HTTP/HTTPS stream URL: read one full JPEG out of the multipart MJPEG
    ///    feed via `MJPEGFrameGrabber` and cancel.
    /// 3. RTSP/RTSPS stream URL: one decoded frame via libvlc
    ///    (`VLCSnapshotGrabber`).
    struct GenericCameraSnapshotProvider: CameraSnapshotProvider {
        let config: GenericCameraConfig
        var grabber: any FrameGrabbing = VLCSnapshotGrabber()

        func snapshot(timeout: TimeInterval) async throws -> Data {
            if let stillURL = config.resolvedStillImageURL() {
                Log.cameraSnapshot.info("Generic snapshot: still URL; t=\(timeout, privacy: .public)s")
                return try await fetchStill(url: stillURL, timeout: timeout)
            }
            guard let streamURL = config.resolvedStreamURL() else {
                Log.cameraSnapshot.notice("Generic snapshot: no usable source")
                throw CameraSnapshotError.noSource
            }
            let scheme = streamURL.scheme?.lowercased() ?? ""
            Log.cameraSnapshot.info(
                "Generic snapshot stream; scheme=\(scheme, privacy: .public) t=\(timeout, privacy: .public)s"
            )
            switch scheme {
            case "rtsp", "rtsps":
                return try await grabber.grab(
                    request: CameraStreamRequest(url: streamURL, transport: config.rtspTransport),
                    timeout: timeout
                )
            case "http", "https":
                return try await fetchMJPEG(url: streamURL, timeout: timeout)
            default:
                throw CameraSnapshotError.unsupportedScheme(scheme)
            }
        }

        private func fetchStill(url: URL, timeout: TimeInterval) async throws -> Data {
            let session = GenericCameraURLSession.make(for: config)
            defer { session.invalidateAndCancel() }
            let deadline = Date().addingTimeInterval(timeout)
            var lastStatus = -1
            var lastError: Error?
            while Date() < deadline {
                let perRequestTimeout = max(0.5, min(2.0, deadline.timeIntervalSinceNow))
                var request = URLRequest(url: url)
                request.setValue(config.contentType, forHTTPHeaderField: "Accept")
                request.timeoutInterval = perRequestTimeout
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                do {
                    let (data, response) = try await session.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if (200 ..< 300).contains(status) {
                        return data
                    }
                    lastStatus = status
                    Log.cameraSnapshot.notice("Generic still HTTP \(status, privacy: .public); retrying")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                    Log.cameraSnapshot.notice(
                        "Generic still error: \(String(describing: error), privacy: .public); retrying"
                    )
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            if let lastError { throw lastError }
            throw CameraSnapshotError.badStatus(lastStatus)
        }

        private func fetchMJPEG(url: URL, timeout: TimeInterval) async throws -> Data {
            let session = GenericCameraURLSession.make(for: config)
            defer { session.invalidateAndCancel() }
            let deadline = Date().addingTimeInterval(timeout)
            var lastError: Error?
            while Date() < deadline {
                let perAttemptTimeout = max(0.5, deadline.timeIntervalSinceNow)
                do {
                    return try await MJPEGFrameGrabber.firstFrame(
                        from: url,
                        session: session,
                        timeout: perAttemptTimeout
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                    Log.cameraSnapshot.notice(
                        "Generic MJPEG error: \(String(describing: error), privacy: .public); retrying"
                    )
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            throw lastError ?? CameraSnapshotError.badStatus(-1)
        }
    }
#endif
