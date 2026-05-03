import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `prusa-link-client` Requirement: Client maps transport and HTTP errors
/// - `prusa-link-client` Requirement: Client authenticates via X-Api-Key
///
/// The tests stand up `URLProtocol` stubs so we drive `URLSessionPrusaLinkClient`
/// against deterministic responses without going to the network.
struct PrusaLinkErrorMappingTests {
    private func makeClient(
        with handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Response
    ) -> URLSessionPrusaLinkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = handler

        let url = URL(string: "http://printer.local")!
        return URLSessionPrusaLinkClient(session: session) {
            PrusaLinkConfiguration(baseURL: url, apiKey: "test-key", timeout: 1)
        }
    }

    @Test
    func missingCredentialsShortCircuits() async {
        let client = URLSessionPrusaLinkClient { nil }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.missingCredentials):
            break
        default:
            Issue.record("Expected .missingCredentials, got \(result)")
        }
    }

    @Test
    func http401MapsToInvalidCredentials() async {
        let client = makeClient { _ in .response(status: 401, body: Data()) }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.invalidCredentials):
            break
        default:
            Issue.record("Expected .invalidCredentials, got \(result)")
        }
    }

    @Test
    func http403MapsToInvalidCredentials() async {
        let client = makeClient { _ in .response(status: 403, body: Data()) }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.invalidCredentials):
            break
        default:
            Issue.record("Expected .invalidCredentials, got \(result)")
        }
    }

    @Test
    func http404MapsToNotFound() async {
        let client = makeClient { _ in .response(status: 404, body: Data()) }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.notFound):
            break
        default:
            Issue.record("Expected .notFound, got \(result)")
        }
    }

    @Test
    func http500MapsToServer() async {
        let client = makeClient { _ in .response(status: 500, body: Data()) }
        let result = await client.fetchStatus()
        switch result {
        case let .failure(.server(status)):
            #expect(status == 500)
        default:
            Issue.record("Expected .server, got \(result)")
        }
    }

    @Test
    func cannotConnectMapsToUnreachable() async {
        let client = makeClient { _ in
            .error(URLError(.cannotConnectToHost))
        }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.unreachable):
            break
        default:
            Issue.record("Expected .unreachable, got \(result)")
        }
    }

    @Test
    func timeoutMapsToUnreachable() async {
        let client = makeClient { _ in
            .error(URLError(.timedOut))
        }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.unreachable):
            break
        default:
            Issue.record("Expected .unreachable, got \(result)")
        }
    }

    @Test
    func malformedJSONMapsToDecoding() async {
        let client = makeClient { _ in
            .response(status: 200, body: Data("not json".utf8))
        }
        let result = await client.fetchStatus()
        switch result {
        case .failure(.decoding):
            break
        default:
            Issue.record("Expected .decoding, got \(result)")
        }
    }

    @Test
    func successfulStatusReturnsDecodedValue() async {
        let json = """
        { "printer": { "state": "IDLE" } }
        """
        let client = makeClient { _ in
            .response(status: 200, body: Data(json.utf8))
        }
        let result = await client.fetchStatus()
        switch result {
        case let .success(status):
            #expect(status.state == .idle)
        case let .failure(error):
            Issue.record("Expected success, got .failure(\(error))")
        }
    }

    @Test
    func apiKeyHeaderIsAttached() async {
        let json = """
        { "printer": { "state": "IDLE" } }
        """
        let recorder = HeaderRecorder()
        let client = makeClient { request in
            recorder.record(request.value(forHTTPHeaderField: "X-Api-Key"))
            return .response(status: 200, body: Data(json.utf8))
        }
        _ = await client.fetchStatus()
        #expect(recorder.value == "test-key")
    }

    @Test
    func http204ForJobReturnsNil() async {
        let client = makeClient { _ in .response(status: 204, body: Data()) }
        let result = await client.fetchJob()
        switch result {
        case let .success(job):
            #expect(job == nil)
        case let .failure(error):
            Issue.record("Expected success(nil), got .failure(\(error))")
        }
    }
}

// MARK: - Helpers

final class HeaderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    func record(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        stored = value
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

// MARK: - Stub URLProtocol

final class StubURLProtocol: URLProtocol {
    enum Response {
        case response(status: Int, body: Data)
        case error(URLError)
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Response)?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch handler(request) {
        case let .response(status, body):
            let url = request.url ?? URL(string: "http://stub")!
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .error(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
