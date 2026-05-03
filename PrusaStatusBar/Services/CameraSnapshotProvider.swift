import Foundation

/// Captures a single still image from one specific camera source. Opaque to
/// the orchestrator (`CameraSnapshotService`) so each source can choose its
/// own transport: go2rtc + `/api/frame.jpeg` for the Buddy camera, plain
/// HTTP GET against a still URL for a generic camera, or an MJPEG one-frame
/// grab when only a stream URL is configured.
protocol CameraSnapshotProvider: Sendable {
    func snapshot(timeout: TimeInterval) async throws -> Data
}

/// Buddy built-in camera (RTSP via go2rtc transmux). Uses `GoRTCService` to
/// register the buddy slot, ensure the helper is running, and GET
/// `/api/frame.jpeg?src=camera`. If the helper had to be spun up just for
/// this snapshot AND the popover is not currently visible, the helper is
/// stopped after a short grace period so it does not outlive the snapshot.
struct BuddyCameraSnapshotProvider: CameraSnapshotProvider {
    let rtspURL: String
    /// Closure rather than a model reference so this stays `Sendable` and
    /// safe to evaluate on the main actor (which is where the popover flag
    /// is mutated). Returns the *current* popover-visible flag at call
    /// time, after the snapshot completes.
    let popoverIsVisible: @Sendable @MainActor () -> Bool

    func snapshot(timeout: TimeInterval) async throws -> Data {
        let wasRunning = await GoRTCService.shared.isHelperRunning
        Log.cameraSnapshot.info(
            "Buddy start; running=\(wasRunning, privacy: .public) t=\(timeout, privacy: .public)s"
        )
        do {
            let data = try await GoRTCService.shared.snapshotJPEG(
                streamName: GoRTCService.snapshotBuddyStreamName,
                source: rtspURL,
                timeout: timeout
            )
            Log.cameraSnapshot.info("Buddy provider succeeded; bytes=\(data.count, privacy: .public)")
            scheduleHelperCleanupIfNeeded(wasRunning: wasRunning)
            return data
        } catch {
            Log.cameraSnapshot.notice("Buddy provider failed: \(String(describing: error), privacy: .public)")
            scheduleHelperCleanupIfNeeded(wasRunning: wasRunning)
            throw error
        }
    }

    private func scheduleHelperCleanupIfNeeded(wasRunning: Bool) {
        guard !wasRunning else { return }
        // Grace period absorbs the rare race where the user opens the
        // dropdown during the snapshot window. If the popover became
        // visible by the time the grace expires, leave the helper running
        // so the tile keeps playing.
        let isVisible = popoverIsVisible
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if isVisible() { return }
            GoRTCService.shared.stop()
        }
    }
}

/// Generic (user-configured) camera. Tries in order:
///
/// 1. Configured still-image URL: single HTTP GET, returns the body bytes
///    as the image. Fastest path because no go2rtc is involved.
/// 2. HTTP/HTTPS stream URL: read one full JPEG out of the multipart MJPEG
///    feed via `MJPEGFrameGrabber` and cancel.
/// 3. RTSP/RTSPS stream URL: register the generic slot in go2rtc and GET
///    `/api/frame.jpeg?src=camera_generic`. Helper cleanup mirrors the
///    Buddy path.
struct GenericCameraSnapshotProvider: CameraSnapshotProvider {
    let config: GenericCameraConfig
    let popoverIsVisible: @Sendable @MainActor () -> Bool

    func snapshot(timeout: TimeInterval) async throws -> Data {
        if let stillURL = config.resolvedStillImageURL() {
            Log.cameraSnapshot.info("Generic provider: still URL path; timeout=\(timeout, privacy: .public)s")
            return try await fetchStill(url: stillURL, timeout: timeout)
        }
        guard let streamURL = config.resolvedStreamURL() else {
            Log.cameraSnapshot.notice("Generic provider: no usable source")
            throw SnapshotError.noSource
        }
        let scheme = streamURL.scheme?.lowercased() ?? ""
        Log.cameraSnapshot.info(
            "Generic stream path; scheme=\(scheme, privacy: .public) t=\(timeout, privacy: .public)s"
        )
        switch scheme {
        case "rtsp", "rtsps":
            return try await fetchViaGoRTC(rtspURL: streamURL.absoluteString, timeout: timeout)
        case "http", "https":
            return try await fetchMJPEG(url: streamURL, timeout: timeout)
        default:
            throw SnapshotError.unsupportedScheme(scheme)
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
        throw SnapshotError.badStatus(lastStatus)
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
        throw lastError ?? SnapshotError.badStatus(-1)
    }

    private func fetchViaGoRTC(rtspURL: String, timeout: TimeInterval) async throws -> Data {
        let wasRunning = await GoRTCService.shared.isHelperRunning
        do {
            let data = try await GoRTCService.shared.snapshotJPEG(
                streamName: GoRTCService.snapshotGenericStreamName,
                source: rtspURL,
                timeout: timeout
            )
            scheduleHelperCleanupIfNeeded(wasRunning: wasRunning)
            return data
        } catch {
            scheduleHelperCleanupIfNeeded(wasRunning: wasRunning)
            throw error
        }
    }

    private func scheduleHelperCleanupIfNeeded(wasRunning: Bool) {
        guard !wasRunning else { return }
        let isVisible = popoverIsVisible
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if isVisible() { return }
            GoRTCService.shared.stop()
        }
    }

    enum SnapshotError: Error, Equatable {
        case noSource
        case unsupportedScheme(String)
        case badStatus(Int)
    }
}
