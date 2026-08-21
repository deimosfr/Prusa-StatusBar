import AppKit
import CoreGraphics
import Foundation
import Observation

/// Identifies a camera tile kind in the dropdown for the per-kind
/// height cache used to keep the placeholder size stable across reopens.
public enum CameraTileKind: String, Hashable, Sendable {
    case buddy
    case generic
}

/// Top-level observable state for the app. Pure data and trivial accessors,
/// the polling loop, notification dispatch and login-item handling live in
/// services that *write to* this model and read its current snapshot.
@MainActor
@Observable
public final class AppModel {
    private static let customActionsDecoder = JSONDecoder()
    private static let customActionsEncoder = JSONEncoder()

    // MARK: - Connection state

    public var lastStatus: PrinterStatus?
    public var lastJob: PrintJob?
    public var lastThumbnail: Data?
    public var lastError: PrusaLinkError?
    public var consecutiveFailures: Int = 0
    public var lastUpdate: Date?
    public var isRefreshing: Bool = false

    // MARK: - Printer info shown in dropdown

    public var printerInfo: PrinterInfo?

    // MARK: - Settings (mirrored from Settings/Keychain so views can observe them)

    public var printerBaseURL: String = ""
    public var apiKeyConfigured: Bool = false
    public var notificationsEnabled: Bool = true
    public var notifyOnStarted: Bool = false
    public var notifyOnFinished: Bool = true
    public var notifyOnAttention: Bool = true
    public var notifyOnError: Bool = true

    /// Mirror of the OS-level `UNAuthorizationStatus` for this app, surfaced
    /// to the UI so the General tab can warn when the master toggle is ON but
    /// macOS will silently swallow every banner. `nil` while the first
    /// async query is in flight.
    public var notificationsAuthorized: Bool?
    public var showRemainingTime: Bool = true
    public var showPercentage: Bool = true
    public var launchAtLogin: Bool = false
    public var refreshIntervalSeconds: Int = UserPreferences.refreshIntervalDefault
    public var disconnectedRefreshIntervalSeconds: Int = UserPreferences.disconnectedRefreshIntervalDefault
    public var showSpeed: Bool = false
    public var showZHeight: Bool = false
    public var showNozzleDiameter: Bool = false
    public var configuredNozzleDiameters: [Double] = []
    public var showFilamentType: Bool = true
    public var showMMU: Bool = false
    public var showTemperatures: Bool = true
    public var showJobActions: Bool = true
    public var showPrusaLinkButton: Bool = true
    public var showPrusaConnectButton: Bool = true
    public var prusaConnectUUID: String = ""
    public var progressBarStyle: ProgressBarStyle = .spool
    public var disconnectedIconStyle: DisconnectedIconStyle = .default
    public var disconnectedIconEmoji: String = UserPreferences.disconnectedIconEmojiDefault
    public var rtspURL: String = ""
    public var accent: Theme.Accent = .orange
    public var customAccentHex: String = UserPreferences.customAccentHexDefault
    public var useKeychainForApiKey: Bool = true
    public var buddyCameraEnabled: Bool = false
    public var genericCameraConfig: GenericCameraConfig = .init()
    public var printerNameOverride: String?
    public var appLanguage: LanguageCode = .system

    /// Reassembled custom action configurations, keyed by slot. Public
    /// half (name, symbol, visibility, ...) hydrates from `UserDefaults`;
    /// secrets (URL, header values, body) are loaded from the Keychain or
    /// plaintext fallback only when the dropdown actually needs to render
    /// them. Slots without a stored config get the all-defaults blank,
    /// so views can bind unconditionally.
    public var customActions: [CustomActionSlot: CustomActionConfig] = AppModel.emptyCustomActions()

    /// Latest GitHub release the `UpdateChecker` has observed and that is
    /// strictly greater than the running app version. Drives the
    /// `FooterBar` "New version available" callout. `nil` hides the
    /// callout.
    public var availableUpdate: GitHubRelease?

    /// Master toggle for the GitHub Releases check. Mirrors
    /// `UserPreferences.checkForUpdatesEnabled` so the General tab can
    /// bind to it. Defaults ON.
    public var checkForUpdatesEnabled: Bool = true

    public static func emptyCustomActions() -> [CustomActionSlot: CustomActionConfig] {
        var result: [CustomActionSlot: CustomActionConfig] = [:]
        for slot in CustomActionSlot.allCases {
            result[slot] = .default
        }
        return result
    }

    // MARK: - UI lifecycle signals

    /// Bumped each time the menu-bar dropdown popover is shown. Views that
    /// need to reset transient animations (e.g. the progress-bar sheen) bind
    /// to this and react to changes.
    public var popoverShowToken: Int = 0

    /// Bumped on every transition into `.printing` from any non-printing
    /// state (idle, ready, busy, stopped, paused). The `MenuBarController`
    /// observes this to play a bounded burst animation, then settle on
    /// `IconPrintingStatic`. Distinct from `notifyOnStarted` (which is a
    /// per-job latch used by the started-notification path), the burst
    /// also fires on resume from pause.
    public var printingBurstToken: Int = 0

    /// True only while the dropdown popover is on screen OR the detached status
    /// window is open. Drives conditional mounting of resource-heavy views
    /// (camera tile + go2rtc helper) so the app does not stream RTSP while
    /// the menu is closed.
    public var popoverVisible: Bool = false

    /// True while the detached status window is open. `MenuBarController` uses
    /// this to route left-clicks to the window instead of toggling the popover.
    public var detachedWindowVisible: Bool = false

    /// Last rendered camera tile height per kind, captured the first time
    /// each tile draws a real frame in the current online session. Drives
    /// placeholder sizing on subsequent reopens so the dropdown does not
    /// reflow while the camera pipeline warms up. Cleared when the printer
    /// transitions to disconnected so a different camera resolution after
    /// reconnect can re-measure cleanly.
    public var cameraTileHeights: [CameraTileKind: CGFloat] = [:]

    public init() {}

    /// Drops every cached camera tile height. Used when the printer goes
    /// offline (and from tests).
    public func clearCameraTileHeights() {
        cameraTileHeights.removeAll(keepingCapacity: true)
    }

    /// Convenience: should the menu-bar surface the "disconnected" affordance?
    /// Per spec, disconnected is shown after ≥ 2 consecutive `.unreachable`
    /// failures so that a single transient blip doesn't flap the icon.
    public var isDisconnected: Bool {
        guard let lastError else {
            return false
        }
        return lastError == .unreachable && consecutiveFailures >= 2
    }

    public var isConfigured: Bool {
        !printerBaseURL.isEmpty && apiKeyConfigured
    }

    /// Manual multi-tool diameters take precedence. With no manual setup the
    /// single value reported by PrusaLink keeps the existing behavior.
    public var effectiveNozzleDiameters: [Double] {
        if configuredNozzleDiameters.count >= 2 {
            return configuredNozzleDiameters
        }
        guard let diameter = printerInfo?.nozzleDiameter, diameter.isFinite, diameter > 0 else {
            return []
        }
        return [diameter]
    }

    /// Refreshes every setting mirror from the injected services so views
    /// observing the model see the same values as on-disk preferences. The
    /// prototype-mode override that fakes "configured" stays in `AppDelegate`
    /// because it is gated by a compile-time flag.
    public func hydrate(from services: AppServices) {
        printerBaseURL = services.settings.printerBaseURL ?? ""
        useKeychainForApiKey = services.settings.useKeychainForApiKey
        apiKeyConfigured = (services.apiKeyStore.read()?.isEmpty == false)
        notificationsEnabled = services.settings.notificationsEnabled
        notifyOnStarted = services.settings.notifyOnStarted
        notifyOnFinished = services.settings.notifyOnFinished
        notifyOnAttention = services.settings.notifyOnAttention
        notifyOnError = services.settings.notifyOnError
        showRemainingTime = services.settings.showRemainingTime
        showPercentage = services.settings.showPercentage
        launchAtLogin = services.loginItem.currentStatus() == .enabled
        refreshIntervalSeconds = services.settings.refreshIntervalSeconds
        disconnectedRefreshIntervalSeconds = services.settings.disconnectedRefreshIntervalSeconds
        showSpeed = services.settings.showSpeed
        showZHeight = services.settings.showZHeight
        showNozzleDiameter = services.settings.showNozzleDiameter
        configuredNozzleDiameters = services.settings.configuredNozzleDiameters
        showFilamentType = services.settings.showFilamentType
        showMMU = services.settings.showMMU
        showTemperatures = services.settings.showTemperatures
        showJobActions = services.settings.showJobActions
        showPrusaLinkButton = services.settings.showPrusaLinkButton
        showPrusaConnectButton = services.settings.showPrusaConnectButton
        prusaConnectUUID = services.settings.prusaConnectUUID ?? ""
        progressBarStyle = services.settings.progressBarStyle
        disconnectedIconStyle = services.settings.disconnectedIconStyle
        disconnectedIconEmoji = services.settings.disconnectedIconEmoji
        rtspURL = services.settings.rtspURL ?? ""
        buddyCameraEnabled = services.settings.buddyCameraEnabled
        genericCameraConfig = GenericCameraConfig.load(
            from: services.settings,
            secretsStore: services.genericCameraSecretsStore
        )
        printerNameOverride = services.settings.printerNameOverride
        accent = services.settings.accent
        customAccentHex = services.settings.customAccentHex
        appLanguage = services.settings.appLanguage
        checkForUpdatesEnabled = services.settings.checkForUpdatesEnabled
        customActions = Self.loadCustomActions(
            from: services.settings,
            secretsStore: services.customActionSecretsStore
        )
    }

    /// Read the persisted public half from `UserDefaults` and reassemble
    /// each slot with secrets pulled from the secrets store. Missing or
    /// malformed JSON falls back to all-default slots so the UI never
    /// crashes on a manually edited preferences plist.
    public static func loadCustomActions(
        from settings: UserPreferences,
        secretsStore: CustomActionSecretsStore
    ) -> [CustomActionSlot: CustomActionConfig] {
        let raw = settings.customActionsPublicJSON
        var publics: [CustomActionSlot: CustomActionPublicConfig] = [:]
        if !raw.isEmpty, let data = raw.data(using: .utf8) {
            if let decoded = try? customActionsDecoder.decode([String: CustomActionPublicConfig].self, from: data) {
                for (key, value) in decoded {
                    if let slot = CustomActionSlot(rawValue: key) {
                        publics[slot] = value
                    }
                }
            }
        }
        var result: [CustomActionSlot: CustomActionConfig] = [:]
        for slot in CustomActionSlot.allCases {
            var pub = publics[slot] ?? CustomActionPublicConfig()
            if pub.symbol == "bolt", pub.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pub.symbol = ""
            }
            let secrets = secretsStore.read(slot: slot)
            result[slot] = CustomActionConfig.assemble(public: pub, secrets: secrets)
        }
        return result
    }

    /// Persist the entire custom-action map. Splits each config into
    /// public + secrets halves and writes the secrets through the store
    /// (Keychain or plaintext fallback per the user's toggle). Errors on
    /// individual slot writes are logged but do not abort the batch:
    /// partial failure leaves at most a stale cached value, never lost
    /// data, since the in-memory model is the source of truth at edit
    /// time.
    public static func saveCustomActions(
        _ actions: [CustomActionSlot: CustomActionConfig],
        to settings: UserPreferences,
        secretsStore: CustomActionSecretsStore
    ) {
        var publics: [String: CustomActionPublicConfig] = [:]
        for slot in CustomActionSlot.allCases {
            let config = actions[slot] ?? .default
            let (pub, secrets) = config.split()
            publics[slot.rawValue] = pub
            do {
                try secretsStore.write(secrets, slot: slot)
            } catch {
                let slotName = slot.rawValue
                let detail = String(describing: error)
                let prefix = "Custom action secrets write failed"
                Log.keychain.error(
                    "\(prefix) for slot \(slotName, privacy: .public): \(detail, privacy: .public)"
                )
            }
        }
        guard let data = try? customActionsEncoder.encode(publics) else { return }
        if let json = String(data: data, encoding: .utf8) {
            settings.customActionsPublicJSON = json
        }
    }

    /// Display name shown as the dropdown title and anywhere else the app
    /// needs a printer name. Precedence: user override > `/api/v1/info` name
    /// > `/api/v1/info` hostname > literal fallback. Hostname is included
    /// because Buddy firmware leaves `name` empty on most printers (MK3.5,
    /// MK4, XL, Core One) and only populates `hostname` (e.g.
    /// `"prusa-core-one"`).
    public var resolvedPrinterName: String {
        let picked: String
        let trimmedOverride = printerNameOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedOverride.isEmpty {
            picked = trimmedOverride
        } else if let apiName = printerInfo?.name, !apiName.isEmpty {
            picked = apiName
        } else if let hostname = printerInfo?.hostname, !hostname.isEmpty {
            picked = hostname
        } else {
            picked = "Prusa StatusBar"
        }
        return String(picked.prefix(AppModel.printerDisplayNameMaxLength))
    }

    public static let printerDisplayNameMaxLength: Int = 30
}
