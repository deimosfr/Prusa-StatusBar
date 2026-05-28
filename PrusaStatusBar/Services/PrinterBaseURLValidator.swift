import Foundation

/// Validates the PrusaLink primary and fallback URL fields on the Printer
/// tab. Pure-syntactic check: trim whitespace, parse with `URL(string:)`,
/// accept only `http` / `https`, and require a non-empty host. Matches the
/// rules of `URLSessionPrusaLinkClient` so an input that passes here is
/// always something the client could later try to connect to.
public enum PrinterBaseURLValidator {
    public enum Result: Equatable {
        case empty
        case valid(URL)
        case invalid
    }

    public static func validate(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty
        else {
            return .invalid
        }
        guard scheme == "http" || scheme == "https" else {
            return .invalid
        }
        guard URLHostValidator.isValid(host: host) else {
            return .invalid
        }
        return .valid(url)
    }
}
