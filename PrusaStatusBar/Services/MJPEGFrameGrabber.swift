import Foundation

/// Reads a single JPEG frame out of an HTTP `multipart/x-mixed-replace`
/// MJPEG stream and cancels the underlying request. Used by the generic
/// camera snapshot provider when only a stream URL is configured: no need
/// to spin up `go2rtc` for HTTP MJPEG, just pull the first frame and stop.
///
/// The parser scans for the JPEG SOI (`0xFF 0xD8`) marker, then the next
/// EOI (`0xFF 0xD9`) marker, and returns the bytes in between (inclusive).
/// It tolerates the multipart boundary headers that arrive between frames
/// because it ignores everything outside the SOI/EOI window.
enum MJPEGFrameGrabber {
    enum GrabError: Error, Equatable {
        case invalidURL
        case badStatus(Int)
        case streamEnded
        case timeout
    }

    /// Capture the first complete JPEG frame from `url`. The session is
    /// invalidated as soon as a complete frame is in hand, so the server
    /// stops streaming the rest of the parts.
    static func firstFrame(
        from url: URL,
        session: URLSession,
        timeout: TimeInterval = 3.0,
        maxBytes: Int = 8 * 1024 * 1024
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("multipart/x-mixed-replace,image/jpeg", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GrabError.badStatus(-1)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw GrabError.badStatus(http.statusCode)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        var prevByte: UInt8 = 0
        var soiIndex: Int?

        for try await byte in bytes {
            if Date() >= deadline {
                throw GrabError.timeout
            }
            if buffer.count >= maxBytes {
                throw GrabError.streamEnded
            }

            buffer.append(byte)
            let lastIndex = buffer.count - 1

            if soiIndex == nil {
                // Looking for SOI: 0xFF 0xD8
                if prevByte == 0xFF, byte == 0xD8 {
                    soiIndex = lastIndex - 1
                }
            } else {
                // Looking for EOI: 0xFF 0xD9
                if prevByte == 0xFF, byte == 0xD9 {
                    let start = soiIndex ?? 0
                    let end = lastIndex + 1
                    return buffer.subdata(in: start ..< end)
                }
            }
            prevByte = byte
        }
        throw GrabError.streamEnded
    }
}
