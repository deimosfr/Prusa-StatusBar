import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `prusa-link-client` Requirement: Client supports an optional fallback base URL
/// - `prusa-link-client` Requirement: Client transparently retries on unreachable using the fallback URL
/// - `prusa-link-client` Requirement: Client caches the active base URL across requests
struct PrusaLinkFallbackRetryTests {
    private let primaryURL = URL(string: "http://primary.local")!
    private let fallbackURL = URL(string: "http://fallback.local")!
    private let statusJSON = Data(#"{ "printer": { "state": "IDLE" } }"#.utf8)

    private func makeClient(
        fallback: URL?,
        handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Response
    ) -> URLSessionPrusaLinkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = handler
        let primary = primaryURL
        return URLSessionPrusaLinkClient(session: session) {
            PrusaLinkConfiguration(
                baseURL: primary,
                apiKey: "test-key",
                fallbackBaseURL: fallback,
                timeout: 1
            )
        }
    }

    @Test
    func noFallbackDoesNotRetry() async {
        let recorder = HostRecorder()
        let client = makeClient(fallback: nil) { request in
            recorder.record(request.url?.host)
            return .error(URLError(.cannotConnectToHost))
        }
        let result = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local"])
        if case .failure(.unreachable) = result {} else {
            Issue.record("Expected .unreachable, got \(result)")
        }
    }

    @Test
    func unreachableTriggersFallbackAndSucceeds() async {
        let recorder = HostRecorder()
        let statusJSON = statusJSON
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            switch request.url?.host {
            case "primary.local":
                return .error(URLError(.cannotConnectToHost))
            default:
                return .response(status: 200, body: statusJSON)
            }
        }
        let result = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local", "fallback.local"])
        if case let .success(status) = result {
            #expect(status.state == .idle)
        } else {
            Issue.record("Expected .success, got \(result)")
        }
    }

    @Test
    func invalidCredentialsDoesNotTriggerFallback() async {
        let recorder = HostRecorder()
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            return .response(status: 401, body: Data())
        }
        let result = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local"])
        if case .failure(.invalidCredentials) = result {} else {
            Issue.record("Expected .invalidCredentials, got \(result)")
        }
    }

    @Test
    func notFoundDoesNotTriggerFallback() async {
        let recorder = HostRecorder()
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            return .response(status: 404, body: Data())
        }
        let result = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local"])
        if case .failure(.notFound) = result {} else {
            Issue.record("Expected .notFound, got \(result)")
        }
    }

    @Test
    func serverErrorDoesNotTriggerFallback() async {
        let recorder = HostRecorder()
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            return .response(status: 500, body: Data())
        }
        let result = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local"])
        if case let .failure(.server(status)) = result {
            #expect(status == 500)
        } else {
            Issue.record("Expected .server(500), got \(result)")
        }
    }

    @Test
    func activeURLStickyAfterFallbackSuccess() async {
        let recorder = HostRecorder()
        let statusJSON = statusJSON
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            switch request.url?.host {
            case "primary.local":
                return .error(URLError(.cannotConnectToHost))
            default:
                return .response(status: 200, body: statusJSON)
            }
        }
        // First call: primary fails, fallback succeeds (2 requests).
        _ = await client.fetchStatus()
        // Second call: should go straight to fallback (1 request, total 3).
        _ = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local", "fallback.local", "fallback.local"])
    }

    @Test
    func activeURLRevertsAfterCacheInvalidation() async {
        let recorder = HostRecorder()
        let statusJSON = statusJSON
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            switch request.url?.host {
            case "primary.local":
                return .error(URLError(.cannotConnectToHost))
            default:
                return .response(status: 200, body: statusJSON)
            }
        }
        _ = await client.fetchStatus()
        client.invalidateConfigurationCache()
        // After invalidation, next call must start from primary again.
        _ = await client.fetchStatus()
        #expect(recorder.requests == [
            "primary.local",
            "fallback.local",
            "primary.local",
            "fallback.local"
        ])
    }

    @Test
    func bothUnreachableReturnsUnreachable() async {
        let recorder = HostRecorder()
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            return .error(URLError(.cannotConnectToHost))
        }
        let result = await client.fetchStatus()
        #expect(recorder.requests == ["primary.local", "fallback.local"])
        if case .failure(.unreachable) = result {} else {
            Issue.record("Expected .unreachable, got \(result)")
        }
    }

    @Test
    func retryAppliesToFetchInfo() async {
        let recorder = HostRecorder()
        let infoJSON = Data(#"{ "name": "lab", "hostname": "lab.local" }"#.utf8)
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            switch request.url?.host {
            case "primary.local":
                return .error(URLError(.timedOut))
            default:
                return .response(status: 200, body: infoJSON)
            }
        }
        let result = await client.fetchInfo()
        #expect(recorder.requests == ["primary.local", "fallback.local"])
        if case let .success(info) = result {
            #expect(info.name == "lab")
        } else {
            Issue.record("Expected .success, got \(result)")
        }
    }

    @Test
    func retryAppliesToFetchJob() async {
        let recorder = HostRecorder()
        let client = makeClient(fallback: fallbackURL) { request in
            recorder.record(request.url?.host)
            switch request.url?.host {
            case "primary.local":
                return .error(URLError(.cannotConnectToHost))
            default:
                return .response(status: 204, body: Data())
            }
        }
        let result = await client.fetchJob()
        #expect(recorder.requests == ["primary.local", "fallback.local"])
        if case let .success(job) = result {
            #expect(job == nil)
        } else {
            Issue.record("Expected .success(nil), got \(result)")
        }
    }
}

// MARK: - Helpers

private final class HostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func record(_ host: String?) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(host ?? "<nil>")
    }

    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
