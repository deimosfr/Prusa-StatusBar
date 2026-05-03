import Foundation

/// Discrete error cases the rest of the app can switch on without inspecting
/// raw `URLError` or `HTTPURLResponse` values.
public enum PrusaLinkError: Error, Equatable, Sendable {
    /// No API key is configured.
    case missingCredentials
    /// The user-supplied base URL is not a valid URL.
    case invalidURL
    /// Printer is not reachable (DNS / TCP / timeout / network down).
    case unreachable
    /// HTTP 401 / 403, the API key is wrong or revoked.
    case invalidCredentials
    /// HTTP 404, endpoint or resource missing.
    case notFound
    /// HTTP 5xx or other unexpected status.
    case server(status: Int)
    /// 200 OK but the body did not match the expected schema.
    case decoding(String)

    public var localizedDescription: String {
        switch self {
        case .missingCredentials:
            "No API key configured"
        case .invalidURL:
            "Printer URL is not valid"
        case .unreachable:
            "Printer unreachable"
        case .invalidCredentials:
            "Invalid API key"
        case .notFound:
            "Resource not found"
        case let .server(status):
            "Printer returned HTTP \(status)"
        case let .decoding(detail):
            "Could not decode printer response: \(detail)"
        }
    }

    /// Localized, user-facing variant of `localizedDescription` for display in
    /// the UI. `localizedDescription` stays English-only on purpose so logs
    /// remain diagnosable across languages.
    @MainActor
    public var localizedUserDescription: String {
        switch self {
        case .missingCredentials:
            L10n.t("error.printer.missing_credentials")
        case .invalidURL:
            L10n.t("error.printer.invalid_url")
        case .unreachable:
            L10n.t("error.printer.unreachable")
        case .invalidCredentials:
            L10n.t("error.printer.invalid_credentials")
        case .notFound:
            L10n.t("error.printer.not_found")
        case let .server(status):
            L10n.t("error.printer.server_status", status)
        case let .decoding(detail):
            L10n.t("error.printer.decoding", detail)
        }
    }
}
