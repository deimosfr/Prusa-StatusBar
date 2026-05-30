import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a `CGImage` to JPEG bytes. Shared by the camera snapshot path
/// (lifted from the former go2rtc MP4 frame grabber so the VLC thumbnailer
/// reuses the same encoder).
enum CGImageJPEG {
    static func data(from cgImage: CGImage, quality: CGFloat = 0.8) -> Data? {
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }
}
