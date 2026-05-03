import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `prusa-link-client` Requirement: Client controls the active job
///   (resume / pause / stop)
///
/// Drives `URLSessionPrusaLinkClient` through the same `StubURLProtocol`
/// machinery as `PrusaLinkErrorMappingTests`, capturing the outgoing
/// request so we can assert HTTP method and path.
struct PrusaLinkJobControlTests {
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

    // MARK: - Pause

    @Test
    func pauseJobIssuesPutAtCorrectPath() async {
        let recorder = RequestRecorder()
        let client = makeClient { request in
            recorder.record(method: request.httpMethod, path: request.url?.path)
            return .response(status: 204, body: Data())
        }
        let result = await client.pauseJob(id: 42)
        switch result {
        case .success:
            break
        case let .failure(error):
            Issue.record("Expected success, got .failure(\(error))")
        }
        #expect(recorder.method == "PUT")
        #expect(recorder.path == "/api/v1/job/42/pause")
    }

    @Test
    func pauseJobOn200IsSuccess() async {
        let client = makeClient { _ in .response(status: 200, body: Data()) }
        let result = await client.pauseJob(id: 1)
        if case .failure = result {
            Issue.record("Expected success on HTTP 200")
        }
    }

    @Test
    func pauseJobOn401MapsToInvalidCredentials() async {
        let client = makeClient { _ in .response(status: 401, body: Data()) }
        let result = await client.pauseJob(id: 1)
        switch result {
        case .failure(.invalidCredentials):
            break
        default:
            Issue.record("Expected .invalidCredentials, got \(result)")
        }
    }

    @Test
    func pauseJobOn409MapsToServer() async {
        let client = makeClient { _ in .response(status: 409, body: Data()) }
        let result = await client.pauseJob(id: 1)
        switch result {
        case let .failure(.server(status)):
            #expect(status == 409)
        default:
            Issue.record("Expected .server(409), got \(result)")
        }
    }

    @Test
    func pauseJobMissingCredentialsShortCircuits() async {
        let client = URLSessionPrusaLinkClient { nil }
        let result = await client.pauseJob(id: 1)
        switch result {
        case .failure(.missingCredentials):
            break
        default:
            Issue.record("Expected .missingCredentials, got \(result)")
        }
    }

    // MARK: - Resume

    @Test
    func resumeJobIssuesPutAtCorrectPath() async {
        let recorder = RequestRecorder()
        let client = makeClient { request in
            recorder.record(method: request.httpMethod, path: request.url?.path)
            return .response(status: 204, body: Data())
        }
        _ = await client.resumeJob(id: 7)
        #expect(recorder.method == "PUT")
        #expect(recorder.path == "/api/v1/job/7/resume")
    }

    // MARK: - Stop

    @Test
    func stopJobIssuesDeleteAtCorrectPath() async {
        let recorder = RequestRecorder()
        let client = makeClient { request in
            recorder.record(method: request.httpMethod, path: request.url?.path)
            return .response(status: 204, body: Data())
        }
        _ = await client.stopJob(id: 99)
        #expect(recorder.method == "DELETE")
        #expect(recorder.path == "/api/v1/job/99")
    }

    @Test
    func stopJobApiKeyHeaderIsAttached() async {
        let recorder = HeaderRecorder()
        let client = makeClient { request in
            recorder.record(request.value(forHTTPHeaderField: "X-Api-Key"))
            return .response(status: 204, body: Data())
        }
        _ = await client.stopJob(id: 1)
        #expect(recorder.value == "test-key")
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMethod: String?
    private var storedPath: String?

    func record(method: String?, path: String?) {
        lock.lock()
        defer { lock.unlock() }
        storedMethod = method
        storedPath = path
    }

    var method: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedMethod
    }

    var path: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedPath
    }
}
