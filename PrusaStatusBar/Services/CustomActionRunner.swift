import Foundation

/// Result of a single custom-action HTTP attempt. Carries enough data to
/// drive the inline test pill in Preferences (status code + duration) and
/// the in-flight feedback on the live button.
public struct CustomActionRunOutcome: Sendable, Equatable {
    public let httpStatus: Int
    public let duration: TimeInterval

    public init(httpStatus: Int, duration: TimeInterval) {
        self.httpStatus = httpStatus
        self.duration = duration
    }

    public var isSuccess: Bool {
        (200 ..< 300).contains(httpStatus)
    }
}

public enum CustomActionError: Error, Equatable, Sendable {
    case invalidURL
    case network(String)
    case timeout
    case nonHTTPResponse
    case slotMissingConfig

    public var displayDescription: String {
        switch self {
        case .invalidURL: "Invalid URL"
        case let .network(message): message
        case .timeout: "Request timed out"
        case .nonHTTPResponse: "Non-HTTP response"
        case .slotMissingConfig: "Slot is not configured"
        }
    }
}

public protocol CustomActionRunning: Sendable {
    func run(_ config: CustomActionConfig) async -> Result<CustomActionRunOutcome, CustomActionError>
}

/// Production runner. Builds a `URLRequest` from the config and executes
/// it on an injected `URLSession`. 15-second per-request timeout.
/// Sandbox-safe: outbound HTTP only, already covered by `network.client`.
public struct LiveCustomActionRunner: CustomActionRunning {
    private let session: URLSession
    private let timeout: TimeInterval
    private let clock: @Sendable () -> Date

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 15,
        clock: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.session = session
        self.timeout = timeout
        self.clock = clock
    }

    public func run(_ config: CustomActionConfig) async -> Result<CustomActionRunOutcome, CustomActionError> {
        let trimmedURL = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.method.rawValue
        request.timeoutInterval = timeout
        for header in config.headers {
            let key = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            request.setValue(header.value, forHTTPHeaderField: key)
        }
        let body = config.body
        if !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
        }

        let start = clock()
        do {
            let (_, response) = try await session.data(for: request)
            let duration = clock().timeIntervalSince(start)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.nonHTTPResponse)
            }
            return .success(CustomActionRunOutcome(httpStatus: http.statusCode, duration: duration))
        } catch let urlError as URLError where urlError.code == .timedOut {
            return .failure(.timeout)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}

/// Stub runner for prototype mode + tests. Returns a synthetic 200 OK
/// after a tiny delay so UI feedback animations have something to react
/// to.
public struct StubCustomActionRunner: CustomActionRunning {
    private let outcome: Result<CustomActionRunOutcome, CustomActionError>
    private let delay: TimeInterval

    public init(
        outcome: Result<CustomActionRunOutcome, CustomActionError> =
            .success(CustomActionRunOutcome(httpStatus: 200, duration: 0.2)),
        delay: TimeInterval = 0.2
    ) {
        self.outcome = outcome
        self.delay = delay
    }

    public func run(_: CustomActionConfig) async -> Result<CustomActionRunOutcome, CustomActionError> {
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return outcome
    }
}
