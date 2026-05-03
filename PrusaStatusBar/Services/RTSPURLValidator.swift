import Foundation

/// Validates the optional RTSP camera URL stored in `UserPreferences`.
/// Trims surrounding whitespace, parses with `URL(string:)`, and accepts
/// only `rtsp` or `rtsps` schemes (case-insensitive). Empty or whitespace-
/// only input maps to `.empty`, which the caller treats as "clear the
/// stored value" rather than as a validation failure.
public enum RTSPURLValidator {
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
              scheme == "rtsp" || scheme == "rtsps"
        else {
            return .invalid
        }
        return .valid(url)
    }
}
