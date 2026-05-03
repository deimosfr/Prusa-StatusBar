import Foundation

/// Orchestrates camera snapshot acquisition for the notification path.
/// Builds an ordered list of `CameraSnapshotProvider`s from current
/// preferences (Buddy first when configured, then Generic), races each
/// against a hard timeout, and returns the first successful image bytes
/// or `nil` if every provider fails or the budget elapses.
public protocol CameraSnapshotService: Sendable {
    /// Returns the JPEG/PNG bytes of the best available camera frame, or
    /// `nil` when no camera is configured, every provider fails, or the
    /// budget elapses. The caller is expected to fall back to the cached
    /// gcode thumbnail in those cases.
    func captureForNotification() async -> Data?
}

#if !PROTOTYPE_MODE
    /// Production snapshot orchestrator. Reads the model on the main actor,
    /// builds non-actor-isolated providers, and races them inside a task
    /// group with a hard deadline. The default budget is 8 seconds: cold
    /// `go2rtc` start plus first-frame RTSP negotiation routinely lands
    /// near 2-3 seconds, and a tighter budget would force most cold-helper
    /// snapshots to fall back to the gcode thumbnail.
    public final class LiveCameraSnapshotService: CameraSnapshotService, @unchecked Sendable {
        private let model: AppModel
        private let timeout: TimeInterval

        public init(model: AppModel, timeout: TimeInterval = 12.0) {
            self.model = model
            self.timeout = timeout
        }

        public func captureForNotification() async -> Data? {
            let providers = await buildProviders()
            guard !providers.isEmpty else {
                Log.cameraSnapshot.info("No camera configured; falling back to thumbnail")
                return nil
            }
            let count = providers.count
            let budget = timeout
            Log.cameraSnapshot.info(
                "Capture start; n=\(count, privacy: .public) budget=\(budget, privacy: .public)s"
            )
            let started = Date()
            let deadline = started.addingTimeInterval(timeout)
            let result = await withTaskGroup(of: Data?.self, returning: Data?.self) { group in
                group.addTask {
                    for provider in providers {
                        let remaining = deadline.timeIntervalSinceNow
                        guard remaining > 0.1 else { return nil }
                        do {
                            return try await provider.snapshot(timeout: remaining)
                        } catch {
                            Log.cameraSnapshot.notice(
                                "Provider failed: \(String(describing: error), privacy: .public)"
                            )
                        }
                    }
                    return nil
                }
                group.addTask {
                    let remaining = max(0, deadline.timeIntervalSinceNow)
                    let nanos = UInt64(remaining * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first ?? nil
            }
            let elapsed = Date().timeIntervalSince(started)
            if let result {
                Log.cameraSnapshot.info(
                    "Capture succeeded; bytes=\(result.count, privacy: .public) elapsed=\(elapsed, privacy: .public)s"
                )
            } else {
                Log.cameraSnapshot.notice(
                    "Capture returned nil; elapsed=\(elapsed, privacy: .public)s (timeout or all providers failed)"
                )
            }
            return result
        }

        /// Picks exactly one camera source: Buddy when configured, else
        /// Generic when configured. Priority is exclusive, not a fallback
        /// chain. If the chosen provider fails or times out, the caller
        /// falls back to the gcode thumbnail; it does NOT try the other
        /// camera. This matches the user-facing contract that "you see
        /// your buddy camera, or the thumbnail, never the wrong camera".
        @MainActor
        private func buildProviders() -> [CameraSnapshotProvider] {
            let popoverFlag: @Sendable @MainActor () -> Bool = { [weak model] in
                model?.popoverVisible ?? false
            }
            if model.buddyCameraEnabled, !model.rtspURL.isEmpty {
                return [BuddyCameraSnapshotProvider(
                    rtspURL: model.rtspURL,
                    popoverIsVisible: popoverFlag
                )]
            }
            if model.genericCameraConfig.enabled, model.genericCameraConfig.hasUsableSource {
                return [GenericCameraSnapshotProvider(
                    config: model.genericCameraConfig,
                    popoverIsVisible: popoverFlag
                )]
            }
            return []
        }
    }
#endif

/// Stub used by prototype mode and tests. Always returns `nil` so the
/// notification path falls back to the cached gcode thumbnail without
/// touching the network or the go2rtc helper.
public final class StubCameraSnapshotService: CameraSnapshotService, @unchecked Sendable {
    public var stubResult: Data?

    public init(stubResult: Data? = nil) {
        self.stubResult = stubResult
    }

    public func captureForNotification() async -> Data? {
        stubResult
    }
}
