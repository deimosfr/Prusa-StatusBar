import Foundation

/// Validates the optional second-camera URLs (stream and still). The two
/// fields share most of the rules: trim whitespace, parse with
/// `URL(string:)`, accept only an explicit allowlist of schemes. The still
/// image field rejects `rtsp` since AVKit cannot consume an RTSP response
/// to a `GET`.
public enum GenericCameraURLValidator {
    public enum Result: Equatable {
        case empty
        case valid(URL)
        case invalid
    }

    public enum Field: Sendable {
        /// Stream Source URL: `rtsp`, `rtsps`, `http`, `https`.
        case stream
        /// Still Image URL: `http`, `https` only.
        case still
    }

    public static func validate(_ raw: String, field: Field) -> Result {
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
        let allowed: Set<String> = switch field {
        case .stream:
            ["rtsp", "rtsps", "http", "https"]
        case .still:
            ["http", "https"]
        }
        guard allowed.contains(scheme) else {
            return .invalid
        }
        guard URLHostValidator.isValid(host: host) else {
            return .invalid
        }
        return .valid(url)
    }
}
