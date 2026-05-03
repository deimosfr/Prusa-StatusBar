import SwiftUI

/// Generic-camera persistence helpers carved out of `PrinterTab` to keep
/// the main file under the lint budget. Same-module extension; the
/// helpers below are not access-restricted and read state via thunks
/// passed in from the call site, since extension files cannot reach
/// `private` `@State` storage.
extension PrinterTab {
    /// Validates and persists the nine Generic Camera fields plus the
    /// password. Validation that fails on a URL field skips the persist
    /// for that field only and surfaces an inline error; valid (or empty)
    /// values are written to disk and mirrored on the model so the
    /// dropdown picks them up on the next refresh.
    func persistGenericCameraConfig(
        snapshot: GenericCameraStateSnapshot,
        streamURLValidation: () -> String?,
        stillURLValidation: () -> String?
    ) throws {
        let validatedStream = streamURLValidation()
        let validatedStill = stillURLValidation()
        services.settings.genericCameraEnabled = snapshot.enabled
        if let value = validatedStream {
            services.settings.genericCameraStreamURL = value
        }
        if let value = validatedStill {
            services.settings.genericCameraStillImageURL = value
        }
        services.settings.genericCameraRTSPTransport = snapshot.rtspTransport
        services.settings.genericCameraAuthMode = snapshot.authMode
        services.settings.genericCameraUsername = snapshot.username
        services.settings.genericCameraFramerate = snapshot.framerate
        services.settings.genericCameraVerifySSL = snapshot.verifySSL
        services.settings.genericCameraContentType = snapshot.contentType
        try services.genericCameraSecretsStore.write(snapshot.password)
        model.genericCameraConfig = GenericCameraConfig.load(
            from: services.settings,
            secretsStore: services.genericCameraSecretsStore
        )
    }

    /// Returns the value to persist for the stream URL, or `nil` to leave
    /// the stored value untouched (validation failed). Empty input maps
    /// to an empty string which the typed accessor normalises to nil.
    static func validateGenericCameraURL(
        raw: String,
        field: GenericCameraURLValidator.Field
    ) -> ValidationOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        switch GenericCameraURLValidator.validate(trimmed, field: field) {
        case let .valid(url): return .valid(url.absoluteString)
        case .empty: return .empty
        case .invalid: return .invalid
        }
    }

    enum ValidationOutcome {
        case empty
        case valid(String)
        case invalid
    }
}
