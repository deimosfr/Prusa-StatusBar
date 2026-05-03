import SwiftUI

/// Equatable bundle of every Generic Camera `@State` value tracked by the
/// Printer tab. Used as the witness for the auto-save `.onChange` so the
/// SwiftUI body stays under the type-checker's complexity ceiling.
struct GenericCameraStateSnapshot: Equatable {
    let enabled: Bool
    let streamURL: String
    let stillImageURL: String
    let rtspTransport: GenericCameraRTSPTransport
    let authMode: GenericCameraAuthMode
    let username: String
    let password: String
    let framerate: Int
    let verifySSL: Bool
    let contentType: String
}

/// Pulled out of the main `PrinterTab` body so the struct stays under the
/// `swiftlint:type_body_length` budget. Same-module extension; the
/// helpers below mutate `@State` storage exposed at internal access.
extension PrinterTab {
    /// Routes a Toggle flip to the confirmation alert. Suppresses the alert
    /// when the value matches what is already persisted, so the revert that
    /// happens on cancel does not loop the dialog.
    func requestKeychainToggle(_ enabled: Bool) {
        if enabled == services.settings.useKeychainForApiKey {
            return
        }
        pendingKeychainToggle = enabled
    }

    func confirmPendingKeychainToggle() {
        guard let enabled = pendingKeychainToggle else { return }
        pendingKeychainToggle = nil
        applyKeychainToggle(enabled)
    }

    func cancelPendingKeychainToggle() {
        pendingKeychainToggle = nil
        useKeychain = services.settings.useKeychainForApiKey
    }

    func applyKeychainToggle(_ enabled: Bool) {
        do {
            try services.apiKeyStore.migrate(toKeychain: enabled)
            try services.customActionSecretsStore.migrate(toKeychain: enabled)
            try services.genericCameraSecretsStore.migrate(toKeychain: enabled)
            services.settings.useKeychainForApiKey = enabled
            model.useKeychainForApiKey = enabled
            apiKey = services.apiKeyStore.read() ?? apiKey
            genericCameraPassword = services.genericCameraSecretsStore.read() ?? genericCameraPassword
            model.customActions = AppModel.loadCustomActions(
                from: services.settings,
                secretsStore: services.customActionSecretsStore
            )
            model.genericCameraConfig = GenericCameraConfig.load(
                from: services.settings,
                secretsStore: services.genericCameraSecretsStore
            )
        } catch {
            useKeychain = !enabled
            let msg = String(format: L10n.t("printer.api_key.migrate_error"), error.localizedDescription)
            primaryTestResult = .failure(msg)
        }
    }
}
