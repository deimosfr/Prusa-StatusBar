import Foundation

/// Derives the canonical Buddy Camera RTSP URL from an IP or DNS host that
/// the user types in the Printer tab. The full RTSP URL is what gets
/// persisted in `UserPreferences.rtspURL`, but the user only ever sees and
/// edits the host - the path (`/live/`) and port (`554`) are conventions of
/// the Prusa Buddy Camera firmware and are baked in.
public enum BuddyCameraHostDeriver {
    public enum DerivationError: Error, Equatable {
        /// Caller passed an empty / whitespace-only host. Treated as "clear
        /// the preference" by the UI, not as a hard error.
        case empty
        /// Host contains a scheme (`://`), an explicit port (`host:1234`),
        /// or other characters that suggest the user pasted a URL instead of
        /// just a host. The UI surfaces an inline "Enter only the IP or
        /// hostname" message in this case.
        case containsSchemeOrPort
    }

    /// Trim and validate a host, returning the derived
    /// `rtsp://<host>:554/live/` URL. Hosts that look like full URLs (contain
    /// `://`) or carry an explicit port (`host:port`) are rejected so the
    /// user is nudged toward a clean host entry.
    public static func rtspURL(forHost rawHost: String) -> Result<URL, DerivationError> {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }
        if trimmed.lowercased().contains("://") {
            return .failure(.containsSchemeOrPort)
        }
        // Bracketed IPv6 (`[::1]`) is allowed; otherwise a colon means the
        // user added a port.
        if trimmed.first != "[", trimmed.contains(":") {
            return .failure(.containsSchemeOrPort)
        }
        guard let url = URL(string: "rtsp://\(trimmed):554/live/") else {
            return .failure(.containsSchemeOrPort)
        }
        guard URLHostValidator.isValid(host: trimmed) else {
            return .failure(.containsSchemeOrPort)
        }
        return .success(url)
    }

    /// Inverse of `rtspURL(forHost:)`: extract just the host from a stored
    /// RTSP URL so the Printer tab can repopulate the field on appear. Any
    /// non-Buddy-Camera-shaped URL falls back to `nil`, in which case the
    /// UI leaves the host field empty.
    public static func host(fromRTSPURL rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host,
              !host.isEmpty
        else {
            return nil
        }
        return host
    }
}
