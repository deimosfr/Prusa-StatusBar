import AppKit
@testable import PrusaStatusBar
import Testing

/// Covers the `JobBackdropRenderer` cache + bake pipeline used by `JobCard`
/// to pre-render the desaturated, blurred backdrop image. The renderer must
/// memoize identical inputs, fail soft on bad data, and produce an image at
/// the requested point size.
struct JobBackdropRendererTests {
    @Test
    func cachesIdenticalInputs() {
        JobBackdropRenderer.clearCache()
        let data = Self.makePNG(width: 32, height: 32, color: .red)
        let size = CGSize(width: 360, height: 200)

        let first = JobBackdropRenderer.render(thumbnail: data, size: size, scale: 1)
        let second = JobBackdropRenderer.render(thumbnail: data, size: size, scale: 1)

        #expect(first != nil)
        #expect(first === second)
    }

    @Test
    func differentDataProducesDifferentImage() {
        JobBackdropRenderer.clearCache()
        let red = Self.makePNG(width: 32, height: 32, color: .red)
        let blue = Self.makePNG(width: 32, height: 32, color: .blue)
        let size = CGSize(width: 360, height: 200)

        let a = JobBackdropRenderer.render(thumbnail: red, size: size, scale: 1)
        let b = JobBackdropRenderer.render(thumbnail: blue, size: size, scale: 1)

        #expect(a != nil)
        #expect(b != nil)
        #expect(a !== b)
    }

    @Test
    func returnsNilForGarbageData() {
        JobBackdropRenderer.clearCache()
        let garbage = Data([0xFF, 0xD8, 0x00, 0x42])
        let result = JobBackdropRenderer.render(
            thumbnail: garbage,
            size: CGSize(width: 360, height: 200),
            scale: 1
        )
        #expect(result == nil)
    }

    @Test
    func outputSizeMatchesRequest() {
        JobBackdropRenderer.clearCache()
        let data = Self.makePNG(width: 64, height: 64, color: .green)
        let size = CGSize(width: 360, height: 200)
        let image = JobBackdropRenderer.render(thumbnail: data, size: size, scale: 2)

        #expect(image?.size == size)
    }

    @Test
    func zeroSizeReturnsNil() {
        JobBackdropRenderer.clearCache()
        let data = Self.makePNG(width: 32, height: 32, color: .red)
        let result = JobBackdropRenderer.render(
            thumbnail: data,
            size: CGSize(width: 0, height: 0),
            scale: 1
        )
        #expect(result == nil)
    }

    private static func makePNG(width: Int, height: Int, color: NSColor) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            Issue.record("Could not allocate NSBitmapImageRep for test fixture")
            return Data()
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
