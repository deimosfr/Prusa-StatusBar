import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` (added) Requirement: custom action buttons fire
///   user-configured HTTP requests and surface non-2xx + network errors.
struct CustomActionRunnerTests {
    private final class Capture: @unchecked Sendable {
        var lastRequest: URLRequest?
        var stubbedResponse: HTTPURLResponse?
        var stubbedData: Data = .init()
        var stubbedError: Error?
    }

    private final class TestProtocol: URLProtocol {
        static let capture = Capture()

        // swiftlint:disable static_over_final_class
        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        // swiftlint:enable static_over_final_class

        override func startLoading() {
            Self.capture.lastRequest = request
            if let error = Self.capture.stubbedError {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response = Self.capture.stubbedResponse {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Self.capture.stubbedData)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    private func makeRunner(
        status: Int? = 200,
        error: Error? = nil
    ) -> LiveCustomActionRunner {
        let url = URL(string: "https://example.com/echo")!
        TestProtocol.capture.lastRequest = nil
        TestProtocol.capture.stubbedError = error
        TestProtocol.capture.stubbedResponse = status.flatMap {
            HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: nil)
        }
        TestProtocol.capture.stubbedData = Data()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestProtocol.self]
        let session = URLSession(configuration: config)
        return LiveCustomActionRunner(session: session, timeout: 5)
    }

    private func sample(
        method: CustomActionMethod = .post,
        body: String = "",
        headers: [CustomActionHeader] = []
    ) -> CustomActionConfig {
        CustomActionConfig(
            enabled: true,
            name: "Power on",
            symbol: "power",
            method: method,
            visibility: .always,
            confirmBeforeRun: false,
            url: "https://example.com/echo",
            headers: headers,
            body: body
        )
    }

    @Test
    func successReturns200Outcome() async {
        let runner = makeRunner(status: 200)
        let outcome = await runner.run(sample())
        switch outcome {
        case let .success(value):
            #expect(value.httpStatus == 200)
            #expect(value.isSuccess)
        case .failure:
            Issue.record("Expected success")
        }
    }

    @Test
    func nonSuccessStatusStillReturnsSuccessWithStatus() async {
        let runner = makeRunner(status: 503)
        let outcome = await runner.run(sample())
        switch outcome {
        case let .success(value):
            #expect(value.httpStatus == 503)
            #expect(!value.isSuccess)
        case .failure:
            Issue.record("Expected success result with non-2xx status")
        }
    }

    @Test
    func networkErrorMapsToFailure() async {
        let runner = makeRunner(
            status: nil,
            error: URLError(.cannotConnectToHost)
        )
        let outcome = await runner.run(sample())
        switch outcome {
        case .success: Issue.record("Expected failure")
        case let .failure(error):
            if case .network = error {
                // Expected.
            } else {
                Issue.record("Expected .network failure, got \(error)")
            }
        }
    }

    @Test
    func timeoutErrorMapsToTimeout() async {
        let runner = makeRunner(
            status: nil,
            error: URLError(.timedOut)
        )
        let outcome = await runner.run(sample())
        switch outcome {
        case .success: Issue.record("Expected failure")
        case let .failure(error):
            #expect(error == .timeout)
        }
    }

    @Test
    func emptyURLReturnsInvalidURL() async {
        let runner = makeRunner()
        var config = sample()
        config.url = "  "
        let outcome = await runner.run(config)
        switch outcome {
        case .success: Issue.record("Expected failure")
        case let .failure(error):
            #expect(error == .invalidURL)
        }
    }

    @Test
    func methodHeadersAndBodyReachRequest() async {
        let runner = makeRunner(status: 204)
        let header = CustomActionHeader(name: "Authorization", value: "Bearer xyz")
        let config = sample(method: .delete, body: "{\"x\":1}", headers: [header])
        _ = await runner.run(config)
        let request = TestProtocol.capture.lastRequest
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer xyz")
        if let bodyData = request?.httpBodyStream?.readAll() {
            #expect(String(data: bodyData, encoding: .utf8) == "{\"x\":1}")
        } else if let body = request?.httpBody {
            #expect(String(data: body, encoding: .utf8) == "{\"x\":1}")
        } else {
            Issue.record("Request body missing")
        }
    }

    @Test
    func emptyHeaderNameIsIgnored() async {
        let runner = makeRunner(status: 200)
        let header = CustomActionHeader(name: "  ", value: "anything")
        let config = sample(headers: [header])
        _ = await runner.run(config)
        // Default URLRequest sets a few headers (e.g. Accept). The blank
        // name must not appear among the configured ones.
        let request = TestProtocol.capture.lastRequest
        let allHeaderKeys = request?.allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []
        #expect(!allHeaderKeys.contains(""))
    }
}

private extension InputStream {
    func readAll(bufferSize: Int = 4096) -> Data? {
        open()
        defer { close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while hasBytesAvailable {
            let read = read(&buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
