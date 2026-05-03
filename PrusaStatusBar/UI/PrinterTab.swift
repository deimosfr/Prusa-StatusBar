import SwiftUI

struct PrinterTab: View {
    @Bindable var model: AppModel
    let services: AppServices

    @State private var url: String = ""
    @State private var fallbackURL: String = ""
    @State private var isFallbackExpanded: Bool = false
    @State var apiKey: String = ""
    @State private var cameraHost: String = ""
    @State private var buddyCameraEnabled: Bool = false
    @State private var genericCameraEnabled: Bool = false
    @State private var genericCameraStreamURL: String = ""
    @State private var genericCameraStillURL: String = ""
    @State private var genericCameraTransport: GenericCameraRTSPTransport = .tcp
    @State private var genericCameraAuthMode: GenericCameraAuthMode = .none
    @State private var genericCameraUsername: String = ""
    @State var genericCameraPassword: String = ""
    @State private var genericCameraFramerate: Int = UserPreferences.genericCameraFramerateDefault
    @State private var genericCameraVerifySSL: Bool = true
    @State private var genericCameraContentType: String = UserPreferences.genericCameraContentTypeDefault
    @State private var genericCameraStreamURLError: String?
    @State private var genericCameraStillURLError: String?
    @State var useKeychain: Bool = true
    /// Drives the keychain-toggle confirmation alert.
    @State var pendingKeychainToggle: Bool?
    @State private var nameOverride: String = ""
    @State private var isApiKeyVisible: Bool = false
    @State var primaryTestResult: PrinterTestResult?
    @State private var fallbackTestResult: PrinterTestResult?
    @State private var isPrimaryTesting: Bool = false
    @State private var isFallbackTesting: Bool = false
    @State private var cameraHostError: String?
    /// Pending debounced auto-save (600 ms). Cancelled on every edit.
    @State private var saveTask: Task<Void, Never>?
    /// Suppresses auto-save while `reloadFromStorage()` is hydrating state.
    @State private var isReloading: Bool = false

    var body: some View {
        Form {
            PrinterSecuritySection(useKeychain: $useKeychain, onChange: requestKeychainToggle)
            Section {
                PrinterApiKeyRow(apiKey: $apiKey, isApiKeyVisible: $isApiKeyVisible)
                PrinterURLRow(
                    url: $url,
                    fallbackURL: $fallbackURL,
                    isFallbackExpanded: $isFallbackExpanded,
                    isPrimaryTesting: isPrimaryTesting,
                    isFallbackTesting: isFallbackTesting,
                    isPrimaryTestDisabled: url.isEmpty || apiKey.isEmpty,
                    isFallbackTestDisabled: fallbackURL.isEmpty || apiKey.isEmpty,
                    primaryTestResult: primaryTestResult,
                    fallbackTestResult: fallbackTestResult,
                    onTestPrimary: { Task { await testPrimary() } },
                    onTestFallback: { Task { await testFallback() } }
                )
                PrinterDisplayNameRow(
                    nameOverride: $nameOverride,
                    placeholder: String(
                        (model.printerInfo?.name ?? "Prusa StatusBar")
                            .prefix(AppModel.printerDisplayNameMaxLength)
                    )
                )
            } header: {
                Text(L10n.t("printer.connection.header"))
            } footer: {
                FormFooterText(L10n.t("printer.display_name.footer"))
            }
            BuddyCameraSection(
                enabled: $buddyCameraEnabled,
                cameraHost: $cameraHost,
                cameraHostError: $cameraHostError,
                probe: services.rtspProbe,
                isPrinterURLSet: isPrinterURLSet
            )
            genericCameraSection
            if !services.settings.notificationsEnabled, model.apiKeyConfigured {
                PrinterNotificationHintSection()
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear { reloadFromStorage() }
        .onDisappear {
            saveTask?.cancel()
            if hasChanges { save() }
        }
        .onChange(of: url) { _, _ in scheduleAutoSave() }
        .onChange(of: fallbackURL) { _, _ in scheduleAutoSave() }
        .onChange(of: apiKey) { _, _ in scheduleAutoSave() }
        .onChange(of: cameraHost) { _, _ in scheduleAutoSave() }
        .onChange(of: buddyCameraEnabled) { _, _ in scheduleAutoSave() }
        .onChange(of: genericCameraSnapshot) { _, _ in scheduleAutoSave() }
        .onChange(of: nameOverride) { _, _ in scheduleAutoSave() }
        .keychainConfirmationAlert(
            pending: $pendingKeychainToggle,
            onConfirm: confirmPendingKeychainToggle,
            onCancel: cancelPendingKeychainToggle
        )
    }

    // MARK: - Derived state

    private var genericCameraSection: some View {
        GenericCameraSection(
            enabled: $genericCameraEnabled,
            streamURL: $genericCameraStreamURL,
            stillImageURL: $genericCameraStillURL,
            rtspTransport: $genericCameraTransport,
            authMode: $genericCameraAuthMode,
            username: $genericCameraUsername,
            password: $genericCameraPassword,
            framerate: $genericCameraFramerate,
            verifySSL: $genericCameraVerifySSL,
            contentType: $genericCameraContentType,
            streamURLError: $genericCameraStreamURLError,
            stillURLError: $genericCameraStillURLError,
            probe: services.rtspProbe,
            isPrinterURLSet: isPrinterURLSet
        )
    }

    /// Single equatable snapshot of every Generic Camera @State value.
    /// Drives a single `.onChange` rather than 11 separate ones, which
    /// the Swift type-checker chokes on inside the `Form` body.
    private var genericCameraSnapshot: GenericCameraStateSnapshot {
        GenericCameraStateSnapshot(
            enabled: genericCameraEnabled,
            streamURL: genericCameraStreamURL,
            stillImageURL: genericCameraStillURL,
            rtspTransport: genericCameraTransport,
            authMode: genericCameraAuthMode,
            username: genericCameraUsername,
            password: genericCameraPassword,
            framerate: genericCameraFramerate,
            verifySSL: genericCameraVerifySSL,
            contentType: genericCameraContentType
        )
    }

    private var isPrinterConfigured: Bool {
        let hasURL = !(services.settings.printerBaseURL ?? "").isEmpty
        let hasKey = (services.apiKeyStore.read()?.isEmpty == false)
        return hasURL && hasKey
    }

    /// Tracks the live `url` field, not the persisted `printerBaseURL`, so the
    /// Buddy Camera toggle re-enables the moment the user finishes typing a URL,
    /// before the debounced auto-save runs.
    private var isPrinterURLSet: Bool {
        BuddyCameraSection.isToggleEnabled(forURLField: url)
    }

    private var derivedRTSPForSave: String {
        let trimmed = cameraHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        switch BuddyCameraHostDeriver.rtspURL(forHost: cameraHost) {
        case let .success(url): return url.absoluteString
        case .failure: return services.settings.rtspURL ?? ""
        }
    }

    private var hasChanges: Bool {
        url != (services.settings.printerBaseURL ?? "")
            || normalisedFallbackURL != (services.settings.printerBaseURLSecondary ?? "")
            || apiKey != (services.apiKeyStore.read() ?? "")
            || derivedRTSPForSave != (services.settings.rtspURL ?? "")
            || buddyCameraEnabled != services.settings.buddyCameraEnabled
            || hasGenericCameraChanges
            || normalisedNameOverride != (services.settings.printerNameOverride ?? "")
    }

    private var hasGenericCameraChanges: Bool {
        let trimmedStream = genericCameraStreamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStill = genericCameraStillURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = genericCameraUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return genericCameraEnabled != services.settings.genericCameraEnabled
            || trimmedStream != (services.settings.genericCameraStreamURL ?? "")
            || trimmedStill != (services.settings.genericCameraStillImageURL ?? "")
            || genericCameraTransport != services.settings.genericCameraRTSPTransport
            || genericCameraAuthMode != services.settings.genericCameraAuthMode
            || trimmedUser != (services.settings.genericCameraUsername ?? "")
            || genericCameraPassword != (services.genericCameraSecretsStore.read() ?? "")
            || genericCameraFramerate != services.settings.genericCameraFramerate
            || genericCameraVerifySSL != services.settings.genericCameraVerifySSL
            || genericCameraContentType != services.settings.genericCameraContentType
    }

    private var normalisedFallbackURL: String {
        fallbackURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalisedNameOverride: String {
        nameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Same-file extension: keeps the struct body under the lint budget while
/// preserving private access to `@State` storage.
private extension PrinterTab {
    func reloadFromStorage() {
        isReloading = true
        defer { isReloading = false }
        url = services.settings.printerBaseURL ?? ""
        fallbackURL = services.settings.printerBaseURLSecondary ?? ""
        apiKey = services.apiKeyStore.read() ?? ""
        useKeychain = services.settings.useKeychainForApiKey
        cameraHost = services.settings.rtspURL.flatMap(BuddyCameraHostDeriver.host(fromRTSPURL:)) ?? ""
        buddyCameraEnabled = services.settings.buddyCameraEnabled
        genericCameraEnabled = services.settings.genericCameraEnabled
        genericCameraStreamURL = services.settings.genericCameraStreamURL ?? ""
        genericCameraStillURL = services.settings.genericCameraStillImageURL ?? ""
        genericCameraTransport = services.settings.genericCameraRTSPTransport
        genericCameraAuthMode = services.settings.genericCameraAuthMode
        genericCameraUsername = services.settings.genericCameraUsername ?? ""
        genericCameraPassword = services.genericCameraSecretsStore.read() ?? ""
        genericCameraFramerate = services.settings.genericCameraFramerate
        genericCameraVerifySSL = services.settings.genericCameraVerifySSL
        genericCameraContentType = services.settings.genericCameraContentType
        genericCameraStreamURLError = nil
        genericCameraStillURLError = nil
        nameOverride = services.settings.printerNameOverride ?? ""
        cameraHostError = nil
    }

    /// Cancels any pending save and schedules a new one ~600 ms after
    /// the most recent edit. Skipped while `reloadFromStorage()` is
    /// repopulating @State, and short-circuited when nothing actually
    /// changed against persisted values.
    private func scheduleAutoSave() {
        if isReloading { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                if hasChanges { save() }
            }
        }
    }

    private func save() {
        let rtspToPersist = validateCameraHost()
        services.settings.printerBaseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        services.settings.printerBaseURLSecondary = fallbackURL
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try persistApiKey(trimmedKey)
            if case let .some(stored) = rtspToPersist {
                services.settings.rtspURL = stored
                model.rtspURL = stored ?? ""
            }
            services.settings.buddyCameraEnabled = buddyCameraEnabled
            model.buddyCameraEnabled = buddyCameraEnabled
            try runGenericCameraPersist()
            services.settings.printerNameOverride = nameOverride
            model.printerNameOverride = services.settings.printerNameOverride
            model.printerBaseURL = url
            model.apiKeyConfigured = !trimmedKey.isEmpty
            services.onConfigurationChanged()
        } catch {
            let msg = String(format: L10n.t("printer.api_key.save_error"), error.localizedDescription)
            primaryTestResult = .failure(msg)
        }
    }

    /// `.none` means leave `rtspURL` untouched (host failed validation),
    /// `.some(nil)` clears the pref, `.some(value)` writes a derived URL.
    private func validateCameraHost() -> String?? {
        let trimmed = cameraHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cameraHostError = nil
            return .some(nil)
        }
        switch BuddyCameraHostDeriver.rtspURL(forHost: cameraHost) {
        case let .success(url):
            if case let .valid(validated) = RTSPURLValidator.validate(url.absoluteString) {
                cameraHostError = nil
                return .some(validated.absoluteString)
            }
            cameraHostError = L10n.t("error.rtsp.invalid")
            return .none
        case .failure(.empty):
            cameraHostError = nil
            return .some(nil)
        case .failure(.containsSchemeOrPort):
            cameraHostError = L10n.t("error.host.invalid")
            return .none
        }
    }

    private func persistApiKey(_ trimmedKey: String) throws {
        if trimmedKey.isEmpty {
            try services.apiKeyStore.delete()
        } else {
            try services.apiKeyStore.write(trimmedKey)
        }
    }

    private func runGenericCameraPersist() throws {
        try persistGenericCameraConfig(
            snapshot: genericCameraSnapshot,
            streamURLValidation: { validateGenericStreamURL() },
            stillURLValidation: { validateGenericStillURL() }
        )
    }

    private func validateGenericStreamURL() -> String? {
        switch Self.validateGenericCameraURL(raw: genericCameraStreamURL, field: .stream) {
        case .empty:
            genericCameraStreamURLError = nil
            return ""
        case let .valid(value):
            genericCameraStreamURLError = nil
            return value
        case .invalid:
            genericCameraStreamURLError = L10n.t("printer.generic_camera.error.invalid_url")
            return nil
        }
    }

    private func validateGenericStillURL() -> String? {
        switch Self.validateGenericCameraURL(raw: genericCameraStillURL, field: .still) {
        case .empty:
            genericCameraStillURLError = nil
            return ""
        case let .valid(value):
            genericCameraStillURLError = nil
            return value
        case .invalid:
            genericCameraStillURLError = L10n.t("printer.generic_camera.error.invalid_url")
            return nil
        }
    }

    @MainActor
    func testPrimary() async {
        isPrimaryTesting = true
        primaryTestResult = nil
        defer { isPrimaryTesting = false }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed) else {
            primaryTestResult = .failure(L10n.t("error.url.invalid"))
            return
        }
        primaryTestResult = await probe(url: parsed, key: apiKey)
    }

    @MainActor
    func testFallback() async {
        isFallbackTesting = true
        fallbackTestResult = nil
        defer { isFallbackTesting = false }
        let trimmed = fallbackURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed) else {
            fallbackTestResult = .failure(L10n.t("error.url.invalid"))
            return
        }
        fallbackTestResult = await probe(url: parsed, key: apiKey)
    }

    func probe(url: URL, key: String) async -> PrinterTestResult {
        let client = URLSessionPrusaLinkClient(configurationProvider: {
            PrusaLinkConfiguration(baseURL: url, apiKey: key)
        })
        switch await client.fetchInfo() {
        case let .success(info):
            return .success(info.name ?? info.hostname ?? L10n.t("printer.test.connected"))
        case let .failure(error):
            return .failure(error.localizedUserDescription)
        }
    }
}
