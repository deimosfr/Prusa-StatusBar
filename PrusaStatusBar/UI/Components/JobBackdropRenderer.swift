import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Pre-bakes the desaturated, blurred backdrop used behind `JobCard` content.
///
/// The previous implementation chained SwiftUI's `.blur(...).scaleEffect(...)`
/// on a small thumbnail every frame. The compositor upscaled an already-blurred
/// low-resolution tile and antialiased the rounded clip against the resampled
/// noisy result, producing speckled edges. Here we render the saturated +
/// blurred bitmap once at the card's display size with CoreImage and memoize
/// the output, so SwiftUI only draws a single opaque texture.
enum JobBackdropRenderer {
    /// NSCache and CIContext are documented thread-safe by Apple, so opt out
    /// of Swift's concurrency-safety check rather than serialising every call
    /// through a global actor.
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8
        return cache
    }()

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Returns a cached blurred backdrop for `thumbnail`, baking it on the
    /// first call. `size` is in points; pixel dimensions are derived from
    /// `scale` (typically the screen's `backingScaleFactor`).
    static func render(
        thumbnail: Data,
        size: CGSize,
        scale: CGFloat = 2,
        radius: CGFloat = 18,
        saturation: CGFloat = 0.6
    ) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let key = cacheKey(
            thumbnail: thumbnail,
            size: size,
            scale: scale,
            radius: radius,
            saturation: saturation
        )
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let baked = bake(
            thumbnail: thumbnail,
            size: size,
            scale: scale,
            radius: radius,
            saturation: saturation
        ) else {
            return nil
        }

        cache.setObject(baked, forKey: key)
        return baked
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

    private static func cacheKey(
        thumbnail: Data,
        size: CGSize,
        scale: CGFloat,
        radius: CGFloat,
        saturation: CGFloat
    ) -> NSString {
        // `Data.hashValue` uses a per-process SipHash seed: stable for the
        // lifetime of this process (which is all the cache needs) but cheap
        // and collision-resistant.
        let dataHash = thumbnail.hashValue
        return "\(dataHash)|\(Int(size.width))x\(Int(size.height))@\(scale)|r\(radius)|s\(saturation)" as NSString
    }

    private static func bake(
        thumbnail: Data,
        size: CGSize,
        scale: CGFloat,
        radius: CGFloat,
        saturation: CGFloat
    ) -> NSImage? {
        guard let source = CIImage(data: thumbnail) else { return nil }

        let saturated = CIFilter.colorControls()
        saturated.inputImage = source
        saturated.saturation = Float(saturation)
        guard let desaturated = saturated.outputImage else { return nil }

        // Aspect-fill scale the source into the requested point size so the
        // gaussian kernel runs on a tile that already covers the card.
        let sourceExtent = desaturated.extent
        let targetPixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let scaleX = targetPixelSize.width / sourceExtent.width
        let scaleY = targetPixelSize.height / sourceExtent.height
        let fillScale = max(scaleX, scaleY)
        let scaled = desaturated.transformed(
            by: CGAffineTransform(scaleX: fillScale, y: fillScale)
        )

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = scaled
        blur.radius = Float(radius * scale)
        guard let blurred = blur.outputImage else { return nil }

        // Gaussian expands the extent; crop back to a centered rect at the
        // requested pixel size so the resulting bitmap has clean opaque edges.
        let scaledExtent = scaled.extent
        let cropRect = CGRect(
            x: scaledExtent.midX - targetPixelSize.width / 2,
            y: scaledExtent.midY - targetPixelSize.height / 2,
            width: targetPixelSize.width,
            height: targetPixelSize.height
        )
        let cropped = blurred.cropped(to: cropRect)

        guard let cgImage = context.createCGImage(cropped, from: cropRect) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: size)
    }
}
