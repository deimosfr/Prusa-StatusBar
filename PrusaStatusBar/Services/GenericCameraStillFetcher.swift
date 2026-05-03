import AppKit
import Foundation
import os

/// Periodically fetches a single image from a configured HTTP endpoint and
/// publishes the latest decoded `NSImage` to subscribers. Runs at the
/// configured frame rate (clamped to [1, 30] fps), handles basic + digest
/// authentication via `URLSession`'s native challenge callback, and
/// optionally accepts self-signed TLS certificates when verify-SSL is OFF.
///
/// Lifetime: the fetcher is started by `GenericCameraTile.onAppear` and
/// stopped on `onDisappear`. A single fetcher instance is reused across
/// config changes; calling `apply(_:)` swaps the in-flight URL/credentials
/// without tearing down the underlying session.
@MainActor
final class GenericCameraStillFetcher {
    enum Update {
        case image(NSImage)
        case failure(String)
    }

    private let logger = Logger(subsystem: "com.deimosfr.prusastatusbar", category: "generic-camera-still")
    private var task: Task<Void, Never>?
    private var config: GenericCameraConfig?
    private let publish: @MainActor (Update) -> Void

    init(publish: @escaping @MainActor (Update) -> Void) {
        self.publish = publish
    }

    func start(config: GenericCameraConfig) {
        self.config = config
        task?.cancel()
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        config = nil
    }

    /// Update the running loop with a new config without restarting it.
    /// Useful when only the framerate or content-type changed.
    func apply(_ config: GenericCameraConfig) {
        self.config = config
    }

    private func runLoop() async {
        while !Task.isCancelled {
            guard let config else { return }
            guard let url = config.resolvedStillImageURL() else {
                publish(.failure("Invalid still image URL"))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            await fetchOnce(url: url, config: config)
            let interval = max(1, min(30, config.framerate))
            let nanos = UInt64(1_000_000_000) / UInt64(interval)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    private func fetchOnce(url: URL, config: GenericCameraConfig) async {
        let session = GenericCameraURLSession.make(for: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue(config.contentType, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                publish(.failure("HTTP \(code)"))
                return
            }
            guard let image = Self.decodeDownsampled(data: data) else {
                publish(.failure("Decode failed"))
                return
            }
            publish(.image(image))
        } catch {
            logger.debug("Still fetch failed: \(error.localizedDescription, privacy: .public)")
            publish(.failure(error.localizedDescription))
        }
    }

    /// Decode the JPEG payload at most `Self.maxThumbnailPixels` on the
    /// long edge. Saves a full-resolution decode when the camera serves a
    /// 1920x1080 frame but the tile renders at a quarter of that. Falls
    /// back to `NSImage(data:)` so an unknown / malformed container is
    /// handled the same way as before.
    private static func decodeDownsampled(data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Long-edge cap that still looks crisp in the camera Quick Look popup
    /// (which can grow up to ~1024pt at 2x scale). The tile itself only
    /// needs ~250px, but downsampling all the way there would make Quick
    /// Look soft.
    private static let maxThumbnailPixels: Int = 1280
}
