import Foundation

/// Production `PrusaLinkClient` backed by `URLSession`. Stateless apart from
/// the configuration provider closure, which is invoked per-request so that
/// changes to the API key / URL take effect on the next poll without recreating
/// the client.
public final class URLSessionPrusaLinkClient: PrusaLinkClient, @unchecked Sendable {
    public typealias ConfigurationProvider = @Sendable () -> PrusaLinkConfiguration?

    private let session: URLSession
    private let configurationProvider: ConfigurationProvider
    private let decoder = JSONDecoder()
    private let cacheLock = NSLock()
    private var cachedConfiguration: PrusaLinkConfiguration?
    private var configurationCached = false
    /// URL the client should try first for the next request. Nil means
    /// "use `configuration.baseURL`". Set to the fallback URL after a
    /// successful retry so steady-state polling does not pay the timeout
    /// cost on every tick while the primary path is down. Cleared by
    /// `invalidateConfigurationCache()` so a Save in Preferences restarts
    /// from the primary URL.
    private var activeBaseURL: URL?

    /// Time-bounded cache for `/api/v1/info`. The endpoint exposes
    /// firmware version, hostname, nozzle diameter and similar
    /// near-static fields that the polling loop hits every cycle but
    /// which barely change between firmware updates. Cached for one
    /// hour, evicted by `invalidateConfigurationCache()` when the user
    /// edits the printer URL or API key.
    private var cachedInfo: (info: PrinterInfo, timestamp: Date)?
    private static let infoCacheTTL: TimeInterval = 3600

    public init(session: URLSession? = nil, configurationProvider: @escaping ConfigurationProvider) {
        self.session = session ?? URLSessionPrusaLinkClient.makePollingSession()
        self.configurationProvider = configurationProvider
    }

    /// Drop the in-memory configuration cache so the next request rereads from
    /// the underlying provider (Keychain or UserDefaults). Call when the user
    /// edits the printer URL or API key in Preferences.
    public func invalidateConfigurationCache() {
        cacheLock.lock()
        cachedConfiguration = nil
        configurationCached = false
        activeBaseURL = nil
        cachedInfo = nil
        cacheLock.unlock()
    }

    /// Returns the URL the next request should target. Prefers the cached
    /// active URL when it still matches one of the configured URLs, else
    /// falls back to the primary `baseURL`. Lock-guarded.
    private func currentActiveURL(for configuration: PrusaLinkConfiguration) -> URL {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = activeBaseURL else { return configuration.baseURL }
        let matchesConfig = cached == configuration.baseURL
            || cached == configuration.fallbackBaseURL
        return matchesConfig ? cached : configuration.baseURL
    }

    private func swapActiveBaseURL(to url: URL) {
        cacheLock.lock()
        activeBaseURL = url
        cacheLock.unlock()
    }

    private func resolveConfiguration() -> PrusaLinkConfiguration? {
        cacheLock.lock()
        if configurationCached {
            let cached = cachedConfiguration
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        let resolved = configurationProvider()
        cacheLock.lock()
        cachedConfiguration = resolved
        configurationCached = true
        cacheLock.unlock()
        return resolved
    }

    private static func makePollingSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 2
        config.waitsForConnectivity = false
        config.httpShouldUsePipelining = false
        return URLSession(configuration: config)
    }

    public func fetchStatus() async -> Result<PrinterStatus, PrusaLinkError> {
        await performJSON(path: "/api/v1/status", as: StatusEnvelopeDTO.self)
            .map(PrusaLinkResponseMapper.map)
    }

    public func fetchJob() async -> Result<PrintJob?, PrusaLinkError> {
        await perform(path: "/api/v1/job") { status, data -> Result<PrintJob?, PrusaLinkError> in
            if status == 204 {
                return .success(nil)
            }
            if (200 ... 299).contains(status) {
                do {
                    let dto = try decoder.decode(JobDetailDTO.self, from: data)
                    return .success(PrusaLinkResponseMapper.map(dto))
                } catch {
                    return .failure(.decoding(error.localizedDescription))
                }
            }
            return .failure(.server(status: status))
        }
    }

    public func fetchThumbnail(at path: String) async -> Result<Data, PrusaLinkError> {
        await perform(path: path) { status, data -> Result<Data, PrusaLinkError> in
            if (200 ... 299).contains(status) {
                return .success(data)
            }
            return .failure(.server(status: status))
        }
    }

    public func fetchInfo() async -> Result<PrinterInfo, PrusaLinkError> {
        if let fresh = cachedInfoIfFresh() {
            return .success(fresh)
        }
        let result = await performJSON(path: "/api/v1/info", as: InfoDTO.self)
            .map(PrusaLinkResponseMapper.map)
        if case let .success(info) = result {
            storeInfoCache(info)
        }
        return result
    }

    public func fetchLegacyMaterial() async -> Result<String?, PrusaLinkError> {
        await performJSON(path: "/api/printer", as: LegacyPrinterDTO.self)
            .map(PrusaLinkResponseMapper.map)
    }

    public func resumeJob(id: Int) async -> Result<Void, PrusaLinkError> {
        await performNoContent(path: "/api/v1/job/\(id)/resume", method: "PUT")
    }

    public func pauseJob(id: Int) async -> Result<Void, PrusaLinkError> {
        await performNoContent(path: "/api/v1/job/\(id)/pause", method: "PUT")
    }

    public func stopJob(id: Int) async -> Result<Void, PrusaLinkError> {
        await performNoContent(path: "/api/v1/job/\(id)", method: "DELETE")
    }

    // MARK: - Private

    private func makeRequest(
        path: String,
        method: String,
        baseURL: URL,
        configuration: PrusaLinkConfiguration
    ) -> Result<URLRequest, PrusaLinkError> {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            return .failure(.invalidURL)
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return .success(request)
    }

    /// Single source of truth for status-code dispatch. Caller-supplied
    /// `decode` only sees status codes outside the auth/not-found shortcuts,
    /// so each public endpoint keeps its body small and focused on shape.
    ///
    /// When `configuration.fallbackBaseURL` is non-nil and the active URL
    /// returns `.unreachable`, the request is retried once against the
    /// alternate URL. Retry is gated to `.unreachable` so a 401/404/5xx
    /// from one URL is not silently re-tried against the other.
    func perform<T>(
        path: String,
        method: String = "GET",
        decode: (_ status: Int, _ data: Data) -> Result<T, PrusaLinkError>
    ) async -> Result<T, PrusaLinkError> {
        guard let configuration = resolveConfiguration() else {
            return .failure(.missingCredentials)
        }

        let primary = currentActiveURL(for: configuration)
        let fallback: URL? = {
            if primary == configuration.baseURL {
                return configuration.fallbackBaseURL
            }
            return configuration.baseURL
        }()

        let firstResult = await execute(
            path: path,
            method: method,
            baseURL: primary,
            configuration: configuration,
            decode: decode
        )
        guard case .failure(.unreachable) = firstResult, let fallback else {
            return firstResult
        }

        let retryResult = await execute(
            path: path,
            method: method,
            baseURL: fallback,
            configuration: configuration,
            decode: decode
        )
        if case .failure(.unreachable) = retryResult {
            // Both paths down: surface the original .unreachable.
            return firstResult
        }
        if case .success = retryResult {
            swapActiveBaseURL(to: fallback)
        }
        return retryResult
    }

    /// Issues a single request against `baseURL` and applies the shared
    /// status-code dispatch. Used by `perform` for the initial attempt
    /// and the optional fallback retry.
    private func execute<T>(
        path: String,
        method: String,
        baseURL: URL,
        configuration: PrusaLinkConfiguration,
        decode: (_ status: Int, _ data: Data) -> Result<T, PrusaLinkError>
    ) async -> Result<T, PrusaLinkError> {
        let request: URLRequest
        switch makeRequest(path: path, method: method, baseURL: baseURL, configuration: configuration) {
        case let .success(req):
            request = req
        case let .failure(error):
            return .failure(error)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.decoding("non-HTTP response"))
            }
            switch http.statusCode {
            case 401, 403:
                return .failure(.invalidCredentials)
            case 404:
                return .failure(.notFound)
            default:
                return decode(http.statusCode, data)
            }
        } catch {
            return .failure(map(transportError: error))
        }
    }

    private func performJSON<T: Decodable>(path: String, as _: T.Type) async -> Result<T, PrusaLinkError> {
        await perform(path: path) { [decoder] status, data -> Result<T, PrusaLinkError> in
            if (200 ... 299).contains(status) {
                do {
                    let decoded = try decoder.decode(T.self, from: data)
                    return .success(decoded)
                } catch {
                    Log.network.error(
                        "Decode failed for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    return .failure(.decoding(error.localizedDescription))
                }
            }
            return .failure(.server(status: status))
        }
    }

    /// Issues a request whose success is signalled by the HTTP status alone
    /// (no body to decode). Used by the job-control endpoints, which return
    /// 200 or 204 on success.
    private func performNoContent(path: String, method: String) async -> Result<Void, PrusaLinkError> {
        await perform(path: path, method: method) { status, _ -> Result<Void, PrusaLinkError> in
            if (200 ... 299).contains(status) {
                return .success(())
            }
            return .failure(.server(status: status))
        }
    }

    private func map(transportError error: Error) -> PrusaLinkError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost,
                 .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotFindHost,
                 .dnsLookupFailed:
                return .unreachable
            default:
                return .decoding(urlError.localizedDescription)
            }
        }
        return .decoding(error.localizedDescription)
    }
}

// MARK: - Info cache helpers

private extension URLSessionPrusaLinkClient {
    func cachedInfoIfFresh() -> PrinterInfo? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = cachedInfo,
              Date().timeIntervalSince(cached.timestamp) < Self.infoCacheTTL
        else {
            return nil
        }
        return cached.info
    }

    func storeInfoCache(_ info: PrinterInfo) {
        cacheLock.lock()
        cachedInfo = (info, Date())
        cacheLock.unlock()
    }
}
