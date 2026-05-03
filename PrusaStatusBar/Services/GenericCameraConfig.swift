import Foundation

/// Resolved configuration for the optional second camera, assembled from
/// `UserPreferences` plus a password read from
/// `GenericCameraSecretsStore`. Pure value type so views can compare
/// snapshots and react via `.onChange` cleanly.
public struct GenericCameraConfig: Sendable, Equatable {
    public enum PreferredMode: Sendable, Equatable {
        case stream(URL)
        case still(URL)
        case none
    }

    public var enabled: Bool
    public var streamURL: String
    public var stillImageURL: String
    public var rtspTransport: GenericCameraRTSPTransport
    public var authMode: GenericCameraAuthMode
    public var username: String
    public var password: String
    public var framerate: Int
    public var verifySSL: Bool
    public var contentType: String

    public init(
        enabled: Bool = false,
        streamURL: String = "",
        stillImageURL: String = "",
        rtspTransport: GenericCameraRTSPTransport = .tcp,
        authMode: GenericCameraAuthMode = .none,
        username: String = "",
        password: String = "",
        framerate: Int = UserPreferences.genericCameraFramerateDefault,
        verifySSL: Bool = true,
        contentType: String = UserPreferences.genericCameraContentTypeDefault
    ) {
        self.enabled = enabled
        self.streamURL = streamURL
        self.stillImageURL = stillImageURL
        self.rtspTransport = rtspTransport
        self.authMode = authMode
        self.username = username
        self.password = password
        self.framerate = framerate
        self.verifySSL = verifySSL
        self.contentType = contentType
    }

    /// Hydrate from `UserPreferences`. The password is read separately
    /// through the secrets store so this initialiser stays free of
    /// Keychain side-effects (handy for prototype mode and tests).
    public static func load(
        from settings: UserPreferences,
        secretsStore: GenericCameraSecretsStore
    ) -> GenericCameraConfig {
        GenericCameraConfig(
            enabled: settings.genericCameraEnabled,
            streamURL: settings.genericCameraStreamURL ?? "",
            stillImageURL: settings.genericCameraStillImageURL ?? "",
            rtspTransport: settings.genericCameraRTSPTransport,
            authMode: settings.genericCameraAuthMode,
            username: settings.genericCameraUsername ?? "",
            password: secretsStore.read() ?? "",
            framerate: settings.genericCameraFramerate,
            verifySSL: settings.genericCameraVerifySSL,
            contentType: settings.genericCameraContentType
        )
    }

    /// True when the user has configured at least one URL that validates.
    /// The dropdown reads this to decide whether to render the tile at all.
    public var hasUsableSource: Bool {
        switch preferredMode {
        case .stream, .still: true
        case .none: false
        }
    }

    /// Picks between the stream URL (preferred) and the still URL based on
    /// validation and presence. The returned URL is the *raw* configured
    /// URL: the go2rtc helper and still fetcher inject credentials and the
    /// `rtsp_transport` query themselves.
    public var preferredMode: PreferredMode {
        if case let .valid(url) = GenericCameraURLValidator.validate(streamURL, field: .stream) {
            return .stream(url)
        }
        if case let .valid(url) = GenericCameraURLValidator.validate(stillImageURL, field: .still) {
            return .still(url)
        }
        return .none
    }

    /// Stream URL as it should be passed to go2rtc: credentials injected
    /// when auth mode is `basic` or `digest`, and `rtsp_transport`
    /// appended for RTSP sources when transport is non-default. Returns
    /// `nil` if the stream URL fails validation.
    public func resolvedStreamURL() -> URL? {
        guard case let .valid(parsed) = GenericCameraURLValidator.validate(streamURL, field: .stream),
              var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        if shouldInjectCredentials, !username.isEmpty {
            components.percentEncodedUser = encodedURLComponent(username)
            if !password.isEmpty {
                components.percentEncodedPassword = encodedURLComponent(password)
            }
        }
        if components.scheme?.lowercased() == "rtsp" || components.scheme?.lowercased() == "rtsps" {
            if rtspTransport != .tcp {
                var items = components.queryItems ?? []
                items.removeAll { $0.name.lowercased() == "rtsp_transport" }
                items.append(URLQueryItem(name: "rtsp_transport", value: rtspTransport.rawValue))
                components.queryItems = items
            }
        }
        return components.url
    }

    /// Still image URL as it should be passed to `URLSession`. Validation
    /// only; credentials travel through `URLAuthenticationChallenge`, not
    /// the URL itself.
    public func resolvedStillImageURL() -> URL? {
        guard case let .valid(url) = GenericCameraURLValidator.validate(stillImageURL, field: .still) else {
            return nil
        }
        return url
    }

    private var shouldInjectCredentials: Bool {
        switch authMode {
        case .basic, .digest: true
        case .none: false
        }
    }

    /// Strict URL component encoding: keep the unreserved set untouched and
    /// percent-encode everything else. `addingPercentEncoding(withAllowedCharacters:)`
    /// returns `nil` only for invalid UTF-16 surrogates which strings
    /// produced by Swift never contain.
    private func encodedURLComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPasswordAllowed
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
