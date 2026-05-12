import Foundation

/// Drives the GitHub Releases poll. At launch, fires one forced check
/// that bypasses the 24h gate so the user always sees a fresh result
/// when they reopen the app. After that, a single `Task` wakes hourly
/// and re-checks whether 24h has elapsed since `lastUpdateCheckDate`.
/// Hydrates `availableUpdate` from `UserPreferences` at init so the
/// FooterBar callout is visible immediately after launch when an
/// update was already known. Failures are silently absorbed and the
/// next attempt fires on the next wake.
@MainActor
public final class UpdateChecker {
    private let model: AppModel
    private let client: GitHubReleaseClient
    private let preferences: UserPreferences
    private let runningVersion: SemanticVersion?
    private let checkInterval: TimeInterval
    private let wakeInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var loopTask: Task<Void, Never>?

    public init(
        model: AppModel,
        client: GitHubReleaseClient,
        preferences: UserPreferences,
        runningVersion: SemanticVersion? = AppVersion.semantic,
        checkInterval: TimeInterval = 24 * 60 * 60,
        wakeInterval: TimeInterval = 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.model = model
        self.client = client
        self.preferences = preferences
        self.runningVersion = runningVersion
        self.checkInterval = checkInterval
        self.wakeInterval = wakeInterval
        self.now = now
        hydrateFromPreferences()
    }

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.run()
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Out-of-band single check. Used by tests and by
    /// `AppServices.onRequestUpdateCheck` (e.g. the General-tab toggle
    /// flipping back ON). Skips the 24h gate.
    public func checkNow() async {
        await performCheck()
    }

    // MARK: - Loop

    private func run() async {
        // Forced launch-time check: bypass the 24h gate so each app
        // start surfaces a fresh result. Records `lastUpdateCheckDate`
        // on success, which re-anchors the hourly loop below.
        if preferences.checkForUpdatesEnabled {
            await performCheck()
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(wakeInterval * 1_000_000_000))
            if shouldCheck() {
                await performCheck()
            }
        }
    }

    private func shouldCheck() -> Bool {
        guard preferences.checkForUpdatesEnabled else { return false }
        guard let last = preferences.lastUpdateCheckDate else { return true }
        return now().timeIntervalSince(last) >= checkInterval
    }

    private func performCheck() async {
        guard preferences.checkForUpdatesEnabled else {
            clearStoredUpdate()
            return
        }
        Log.network.notice("Update check: fetching latest release")
        let result = await client.fetchLatestRelease()
        switch result {
        case let .success(release):
            preferences.lastUpdateCheckDate = now()
            let runningDescription = runningVersion
                .map { "\($0.major).\($0.minor).\($0.patch)" } ?? "nil"
            Log.network.notice(
                "Update check: latest=\(release.tag, privacy: .public) running=\(runningDescription, privacy: .public)"
            )
            apply(release: release)
        case let .failure(error):
            Log.network.notice("Update check failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func apply(release: GitHubRelease) {
        guard let runningVersion, let latest = SemanticVersion(release.tag) else {
            // Cannot compare: clear stored update state so a previously
            // surfaced callout disappears once we get an unparseable
            // response in a follow-up tick.
            clearStoredUpdate()
            return
        }
        if latest > runningVersion {
            preferences.latestUpdateTag = release.tag
            preferences.latestUpdateURL = release.htmlURL
            model.availableUpdate = release
        } else {
            clearStoredUpdate()
        }
    }

    private func clearStoredUpdate() {
        preferences.latestUpdateTag = nil
        preferences.latestUpdateURL = nil
        model.availableUpdate = nil
    }

    private func hydrateFromPreferences() {
        guard let tag = preferences.latestUpdateTag,
              let url = preferences.latestUpdateURL
        else {
            model.availableUpdate = nil
            return
        }
        // Re-validate against the running version so a stale "newer" tag
        // from a prior install is not surfaced after the user upgrades.
        if let runningVersion, let latest = SemanticVersion(tag), latest <= runningVersion {
            clearStoredUpdate()
            return
        }
        model.availableUpdate = GitHubRelease(tag: tag, htmlURL: url)
    }
}
