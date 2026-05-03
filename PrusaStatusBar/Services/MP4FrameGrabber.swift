import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Captures a single JPEG frame by downloading a short MP4 from go2rtc
/// (`/api/stream.mp4?src=NAME&duration=N`) and pulling the first decoded
/// frame out of the resulting VOD asset with `AVAssetImageGenerator`.
///
/// Why not the obvious endpoints:
///   * `/api/frame.jpeg?src=NAME` returns HTTP 500 on the Prusa Buddy
///     H264 source even after the producer reports bytes.
///   * `/api/stream.mjpeg?src=NAME` opens but the transmuxer closes the
///     connection before emitting a complete JPEG, repeatedly.
///   * `/api/stream.m3u8?src=NAME` is a live HLS playlist and
///     `AVAssetImageGenerator` rejects live HLS with
///     `kFigBaseObjectError_PropertyNotSupported`.
///
/// The MP4 endpoint produces a finite, well-formed MP4 (one keyframe is
/// enough to decode the first frame). Saved to a temp file, AVFoundation
/// happily generates an image from it.
enum MP4FrameGrabber {
    enum GrabError: Error, Equatable {
        case timeout
        case badStatus(Int)
        case download
        case decode
        case encodingFailed
    }

    /// Downloads a `duration`-second MP4 from `url` and returns JPEG bytes
    /// of the first decodable frame. Cancellation propagates through both
    /// the URLSession download and the image generator.
    static func firstFrame(
        from url: URL,
        deadline: Date,
        duration _: Double = 1.0
    ) async throws -> Data {
        let mp4 = try await downloadMP4(url: url, deadline: deadline)
        let cg = try await decodeFirstFrame(mp4: mp4)
        guard let data = jpegData(from: cg) else {
            throw GrabError.encodingFailed
        }
        return data
    }

    private static func downloadMP4(url: URL, deadline: Date) async throws -> URL {
        let remaining = max(1.0, deadline.timeIntervalSinceNow)
        var request = URLRequest(url: url)
        request.timeoutInterval = remaining
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw GrabError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw GrabError.download }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("prusa-snap-\(UUID().uuidString).mp4")
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    private static func decodeFirstFrame(mp4: URL) async throws -> CGImage {
        defer { try? FileManager.default.removeItem(at: mp4) }
        let box = GeneratorBox(url: mp4)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                box.generator.generateCGImagesAsynchronously(
                    forTimes: [NSValue(time: .zero)]
                ) { _, image, _, _, error in
                    if let image {
                        continuation.resume(returning: image)
                        return
                    }
                    continuation.resume(throwing: error ?? GrabError.decode)
                }
            }
        } onCancel: {
            box.generator.cancelAllCGImageGeneration()
        }
    }

    /// `AVAssetImageGenerator` is not declared `Sendable`. The boxed
    /// reference is shared between the in-flight async work and the
    /// cancellation handler, both of which run from the same task.
    private final class GeneratorBox: @unchecked Sendable {
        let generator: AVAssetImageGenerator

        init(url: URL) {
            let asset = AVURLAsset(url: url)
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .positiveInfinity
        }
    }

    private static func jpegData(from cgImage: CGImage) -> Data? {
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutable as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutable as Data
    }
}
