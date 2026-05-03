import Foundation

/// Snapshot endpoint accessors for the notification path. Carved out of
/// `GoRTCService.swift` so the main file stays under the `file_length`
/// lint budget. Internal access on `host`, `dependenciesView`,
/// `isHelperRunning`, the stream-slot constants, and `upsertStream` keeps
/// this extension fully decoupled from the main type's `private` storage.
extension GoRTCService {
    /// Capture a single JPEG frame from a configured stream slot.
    ///
    /// Sequence:
    /// 1. `upsertStream` registers the slot; this implicitly spawns the
    ///    helper subprocess if it was not running yet.
    /// 2. `waitForAPIReachable` waits for the helper to bind its loopback
    ///    HTTP port.
    /// 3. `waitForSourceReady` polls `/api/streams?src=<name>` until
    ///    go2rtc reports the upstream RTSP source has a connected
    ///    producer. This is the equivalent of the user's manual
    ///    "start go2rtc and wait 4-5s before grabbing a frame" workflow:
    ///    `/api/frame.jpeg` will return HTTP 500 ("no producer yet")
    ///    until the source attaches, so we explicitly wait instead of
    ///    burning the budget on retry-on-500.
    /// 4. Single GET on `/api/frame.jpeg?src=<name>` with the remaining
    ///    budget. Once the producer is attached, a frame should land
    ///    inside one keyframe interval.
    ///
    /// The helper lifecycle (start, stop) is the caller's responsibility;
    /// this method just uses whichever helper happens to be running.
    func snapshotJPEG(
        streamName: String,
        source: String,
        timeout: TimeInterval = 3.0
    ) async throws -> Data {
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        guard upsertStream(name: streamName, source: source) != nil else {
            Log.cameraSnapshot.error("go2rtc helper binary unavailable")
            throw SnapshotError.helperUnavailable
        }
        try await waitForAPIReachable(deadline: deadline)
        Log.cameraSnapshot.info(
            "go2rtc API ready; t=\(Date().timeIntervalSince(started), privacy: .public)s"
        )

        try await waitForSourceReady(streamName: streamName, deadline: deadline)
        Log.cameraSnapshot.info(
            "go2rtc source ready; t=\(Date().timeIntervalSince(started), privacy: .public)s"
        )

        // `/api/frame.jpeg` returns HTTP 500 on the Buddy H264 stream,
        // `/api/stream.mjpeg` closes the connection before emitting a
        // complete JPEG, and `AVAssetImageGenerator` rejects live HLS
        // playlists. The MP4 endpoint serves a finite VOD MP4 (one
        // keyframe is enough), which AVFoundation can decode from a
        // local file without any of those issues.
        guard let url = streamMP4URL(streamName: streamName) else {
            throw SnapshotError.invalidURL
        }
        return try await pollMP4Frame(url: url, deadline: deadline, started: started)
    }

    /// Retries the MP4 download + decode until success or deadline. On a
    /// cold buddy camera the first request can return an MP4 that is
    /// short of even one keyframe; in that case AVAssetImageGenerator
    /// reports `decode`/`noFrame` and we ask go2rtc for another MP4.
    private func pollMP4Frame(url: URL, deadline: Date, started: Date) async throws -> Data {
        var lastError: Error?
        while Date() < deadline {
            do {
                let data = try await MP4FrameGrabber.firstFrame(from: url, deadline: deadline)
                let elapsed = Date().timeIntervalSince(started)
                Log.cameraSnapshot.info(
                    "MP4 frame ok; n=\(data.count, privacy: .public) t=\(elapsed, privacy: .public)s"
                )
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                Log.cameraSnapshot.notice(
                    "MP4 attempt failed: \(String(describing: error), privacy: .public); retrying"
                )
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw lastError ?? SnapshotError.readinessTimeout
    }

    /// Polls `/api/streams?src=<name>` and returns when go2rtc reports
    /// the upstream source has at least one connected producer. The first
    /// request also nudges go2rtc to attach to the source if it has not
    /// yet, so this loop both probes and warms up.
    private func waitForSourceReady(streamName: String, deadline: Date) async throws {
        guard let url = streamInfoURL(streamName: streamName) else {
            throw SnapshotError.invalidURL
        }
        while Date() < deadline {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 1.0
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if status == 200, sourceHasProducer(in: data) {
                    return
                }
                Log.cameraSnapshot.debug(
                    "source not ready; HTTP \(status, privacy: .public); retrying"
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Log.cameraSnapshot.debug(
                    "source check error: \(String(describing: error), privacy: .public); retrying"
                )
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw SnapshotError.readinessTimeout
    }

    /// Returns true when the parsed `/api/streams?src=...` response shows
    /// a producer that has actually received bytes from the upstream
    /// source. go2rtc reports a producer as soon as the TCP/RTSP socket
    /// is set up, but `/api/frame.jpeg` keeps returning HTTP 500 until
    /// the producer has a decoded frame. The `recv` (or `bytes_recv`)
    /// field on each producer is the cleanest "frames are flowing now"
    /// signal go2rtc exposes. Falls back to "any producer present" when
    /// the field is missing on older builds.
    private func sourceHasProducer(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        guard let dict = json as? [String: Any] else { return false }
        if let producers = dict["producers"] as? [Any], producersHaveBytes(producers) {
            return true
        }
        // Multi-stream shape: any nested stream with active producers.
        for value in dict.values where nestedHasActiveProducer(value) {
            return true
        }
        return false
    }

    private func producersHaveBytes(_ producers: [Any]) -> Bool {
        guard !producers.isEmpty else { return false }
        var sawRecvField = false
        for entry in producers {
            guard let producer = entry as? [String: Any] else { continue }
            if let recv = producerRecvBytes(producer) {
                sawRecvField = true
                if recv > 0 { return true }
            }
        }
        // Older go2rtc builds do not expose recv; treat any producer as
        // ready so we do not stall forever on a field that does not exist.
        return !sawRecvField
    }

    private func producerRecvBytes(_ producer: [String: Any]) -> Int? {
        if let recv = producer["recv"] as? Int { return recv }
        if let recv = producer["recv"] as? Double { return Int(recv) }
        if let recv = producer["bytes_recv"] as? Int { return recv }
        if let recv = producer["bytes_recv"] as? Double { return Int(recv) }
        return nil
    }

    private func nestedHasActiveProducer(_ value: Any) -> Bool {
        guard let nested = value as? [String: Any] else { return false }
        guard let producers = nested["producers"] as? [Any] else { return false }
        return producersHaveBytes(producers)
    }

    private func waitForAPIReachable(deadline: Date) async throws {
        guard let url = snapshotStreamsURL() else { throw SnapshotError.invalidURL }
        while Date() < deadline {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 0.5
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return
                }
            } catch {
                // Helper may not be listening yet; small backoff and retry.
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw SnapshotError.readinessTimeout
    }

    private func streamMP4URL(streamName: String) -> URL? {
        let items = [
            URLQueryItem(name: "src", value: streamName),
            URLQueryItem(name: "duration", value: "1")
        ]
        return buildURL(path: "/api/stream.mp4", queryItems: items)
    }

    private func snapshotStreamsURL() -> URL? {
        buildURL(path: "/api/streams", queryItems: nil)
    }

    private func streamInfoURL(streamName: String) -> URL? {
        buildURL(path: "/api/streams", queryItems: [URLQueryItem(name: "src", value: streamName)])
    }

    private func buildURL(path: String, queryItems: [URLQueryItem]?) -> URL? {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = Int(dependenciesView.port)
        c.path = path
        c.queryItems = queryItems
        return c.url
    }

    enum SnapshotError: Error, Equatable {
        case helperUnavailable
        case invalidURL
        case readinessTimeout
        case badStatus(Int)
        case invalidJPEG
    }
}
