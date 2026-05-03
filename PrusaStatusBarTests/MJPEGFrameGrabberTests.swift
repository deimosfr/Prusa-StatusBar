import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage: `notifications` Requirement -- live snapshot for generic
/// cameras when only a stream URL is configured. The grabber must read one
/// complete JPEG frame from a `multipart/x-mixed-replace` MJPEG response and
/// stop reading the rest.
struct MJPEGFrameGrabberTests {
    @Test
    func extractsFirstJPEGFromMultipartStream() async throws {
        // Tiny synthetic JPEG: SOI ... EOI. Content between markers is
        // arbitrary as long as the parser does not collapse it.
        let firstFrame = Data([0xFF, 0xD8, 0x01, 0x02, 0x03, 0x04, 0xFF, 0xD9])
        let secondFrame = Data([0xFF, 0xD8, 0x99, 0x88, 0x77, 0xFF, 0xD9])
        let body = makeMultipartBody(boundary: "--boundary", frames: [firstFrame, secondFrame])

        let url = try URL.randomLocalhost()
        MJPEGStubURLProtocol.responses[url] = MJPEGStubURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "multipart/x-mixed-replace; boundary=boundary"],
            body: body
        )
        defer { MJPEGStubURLProtocol.responses.removeValue(forKey: url) }

        let session = MJPEGStubURLProtocol.session()
        let extracted = try await MJPEGFrameGrabber.firstFrame(
            from: url,
            session: session,
            timeout: 2
        )

        #expect(extracted == firstFrame, "grabber must return the first JPEG verbatim")
    }

    @Test
    func failsCleanlyOnNonOKStatus() async throws {
        let url = try URL.randomLocalhost()
        MJPEGStubURLProtocol.responses[url] = MJPEGStubURLProtocol.Response(
            statusCode: 503,
            headers: [:],
            body: Data()
        )
        defer { MJPEGStubURLProtocol.responses.removeValue(forKey: url) }

        let session = MJPEGStubURLProtocol.session()
        await #expect(throws: MJPEGFrameGrabber.GrabError.self) {
            _ = try await MJPEGFrameGrabber.firstFrame(
                from: url,
                session: session,
                timeout: 1
            )
        }
    }

    private func makeMultipartBody(boundary: String, frames: [Data]) -> Data {
        var body = Data()
        for frame in frames {
            body.append(Data("\(boundary)\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n".utf8))
            body.append(Data("Content-Length: \(frame.count)\r\n\r\n".utf8))
            body.append(frame)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("\(boundary)--\r\n".utf8))
        return body
    }
}

/// Minimal `URLProtocol` stub that serves preconfigured byte bodies for
/// specific URLs. Used in place of a real HTTP server so the MJPEG parser
/// can be tested deterministically without flakiness from networking.
private final class MJPEGStubURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var responses: [URL: Response] = [:]

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MJPEGStubURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return responses[url] != nil
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let response = MJPEGStubURLProtocol.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )
        // swiftlint:disable:next force_unwrapping
        client?.urlProtocol(self, didReceive: httpResponse!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URL {
    static func randomLocalhost() throws -> URL {
        let path = "/stub/\(UUID().uuidString)"
        guard let url = URL(string: "http://localhost\(path)") else {
            throw URLError(.badURL)
        }
        return url
    }
}
