import Foundation

/// HTTP authentication scheme used for the optional second camera. Mirrors
/// the Home Assistant Generic Camera integration vocabulary so users coming
/// from HA see familiar terminology. `none` is the default; basic and digest
/// route through `URLSession`'s native challenge handling.
public enum GenericCameraAuthMode: String, CaseIterable, Sendable {
    case none
    case basic
    case digest
}

/// RTSP transport hint passed to the bundled go2rtc helper as the
/// `rtsp_transport` query parameter on the source URL. Defaults to `tcp`,
/// the only transport that works through most NAT and firewall setups.
public enum GenericCameraRTSPTransport: String, CaseIterable, Sendable {
    case tcp
    case udp
    case udpMulticast = "udp_multicast"
    case http
}

/// Generic Camera persistence accessors carved out of `UserPreferences` so
/// that file stays under the lint budget. The split mirrors the public /
/// secrets divide: this file owns only the non-sensitive half plus the
/// plaintext fallback that activates when the Keychain toggle is off.
public extension UserPreferences {
    static let genericCameraFramerateDefault = 2
    static let genericCameraFramerateMin = 1
    static let genericCameraFramerateMax = 30
    static let genericCameraContentTypeDefault = "image/jpeg"

    /// Master toggle for the optional second camera section in the Printer
    /// tab. Defaults OFF so the dropdown stays slim until the user opts in,
    /// matching Buddy Camera's pattern.
    var genericCameraEnabled: Bool {
        get { defaultsAccess.bool(forKey: UserPreferencesKey.genericCameraEnabled) }
        set { defaultsAccess.set(newValue, forKey: UserPreferencesKey.genericCameraEnabled) }
    }

    /// Optional HTTP(S) endpoint returning a single image. Polled at the
    /// configured frame rate when the stream URL is empty or fails. Empty
    /// or whitespace-only input normalises to nil on read.
    var genericCameraStillImageURL: String? {
        get { trimmedString(forKey: UserPreferencesKey.genericCameraStillImageURL) }
        set { writeTrimmed(newValue, forKey: UserPreferencesKey.genericCameraStillImageURL) }
    }

    /// Optional `rtsp://`, `http://`, or `https://` source URL. RTSP and
    /// HTTP MJPEG sources are routed through the bundled go2rtc helper.
    var genericCameraStreamURL: String? {
        get { trimmedString(forKey: UserPreferencesKey.genericCameraStreamURL) }
        set { writeTrimmed(newValue, forKey: UserPreferencesKey.genericCameraStreamURL) }
    }

    var genericCameraRTSPTransport: GenericCameraRTSPTransport {
        get {
            guard let raw = defaultsAccess.string(forKey: UserPreferencesKey.genericCameraRTSPTransport),
                  let value = GenericCameraRTSPTransport(rawValue: raw)
            else {
                return .tcp
            }
            return value
        }
        set { defaultsAccess.set(newValue.rawValue, forKey: UserPreferencesKey.genericCameraRTSPTransport) }
    }

    var genericCameraAuthMode: GenericCameraAuthMode {
        get {
            guard let raw = defaultsAccess.string(forKey: UserPreferencesKey.genericCameraAuthMode),
                  let value = GenericCameraAuthMode(rawValue: raw)
            else {
                return .none
            }
            return value
        }
        set { defaultsAccess.set(newValue.rawValue, forKey: UserPreferencesKey.genericCameraAuthMode) }
    }

    var genericCameraUsername: String? {
        get { trimmedString(forKey: UserPreferencesKey.genericCameraUsername) }
        set { writeTrimmed(newValue, forKey: UserPreferencesKey.genericCameraUsername) }
    }

    /// Plaintext fallback slot for the camera password, used only when
    /// `useKeychainForApiKey == false`. The Keychain remains the default;
    /// this slot is kept `nil` whenever the toggle is ON.
    var genericCameraPasswordPlaintext: String? {
        get { defaultsAccess.string(forKey: UserPreferencesKey.genericCameraPasswordPlaintext) }
        set {
            if let value = newValue, !value.isEmpty {
                defaultsAccess.set(value, forKey: UserPreferencesKey.genericCameraPasswordPlaintext)
            } else {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.genericCameraPasswordPlaintext)
            }
        }
    }

    /// Frame rate (fps) for the still-image polling loop. Defaults to 2 (HA
    /// parity), clamped to [1, 30] on read so a manual `defaults write`
    /// cannot drive the poller out of bounds.
    var genericCameraFramerate: Int {
        get {
            if defaultsAccess.object(forKey: UserPreferencesKey.genericCameraFramerate) == nil {
                return Self.genericCameraFramerateDefault
            }
            let raw = defaultsAccess.integer(forKey: UserPreferencesKey.genericCameraFramerate)
            return max(Self.genericCameraFramerateMin, min(Self.genericCameraFramerateMax, raw))
        }
        set {
            let clamped = max(
                Self.genericCameraFramerateMin,
                min(Self.genericCameraFramerateMax, newValue)
            )
            defaultsAccess.set(clamped, forKey: UserPreferencesKey.genericCameraFramerate)
        }
    }

    /// Whether the still-image fetcher should validate the server's TLS
    /// certificate. Defaults ON. When OFF, the fetcher answers server-trust
    /// challenges with `URLCredential(trust:)`, scoped to that session only.
    var genericCameraVerifySSL: Bool {
        get {
            if defaultsAccess.object(forKey: UserPreferencesKey.genericCameraVerifySSL) == nil {
                return true
            }
            return defaultsAccess.bool(forKey: UserPreferencesKey.genericCameraVerifySSL)
        }
        set { defaultsAccess.set(newValue, forKey: UserPreferencesKey.genericCameraVerifySSL) }
    }

    /// `Accept` header sent on still-image GETs. Defaults to `image/jpeg`.
    /// Empty input normalises to the default on read.
    var genericCameraContentType: String {
        get {
            let raw = defaultsAccess.string(forKey: UserPreferencesKey.genericCameraContentType) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Self.genericCameraContentTypeDefault : trimmed
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.genericCameraContentType)
            } else {
                defaultsAccess.set(trimmed, forKey: UserPreferencesKey.genericCameraContentType)
            }
        }
    }

    private func trimmedString(forKey key: String) -> String? {
        guard let raw = defaultsAccess.string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeTrimmed(_ value: String?, forKey key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaultsAccess.set(trimmed, forKey: key)
        } else {
            defaultsAccess.removeObject(forKey: key)
        }
    }
}
