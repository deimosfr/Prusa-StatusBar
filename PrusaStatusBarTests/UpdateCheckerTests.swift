import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `update-check` Requirements: poll cadence, version compare, silent
///   failure, footer callout state.
@MainActor
struct UpdateCheckerTests {
    private func makePreferences() -> (UserPreferences, UserDefaults) {
        let suite = "PrusaStatusBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserPreferences(defaults: defaults), defaults)
    }

    private struct Harness {
        let checker: UpdateChecker
        let model: AppModel
        let prefs: UserPreferences
    }

    private func makeHarness(
        client: GitHubReleaseClient,
        running: SemanticVersion = SemanticVersion(major: 1, minor: 0, patch: 0),
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Harness {
        let model = AppModel()
        let (prefs, _) = makePreferences()
        let checker = UpdateChecker(
            model: model,
            client: client,
            preferences: prefs,
            runningVersion: running,
            now: { now }
        )
        return Harness(checker: checker, model: model, prefs: prefs)
    }

    @Test
    func newerReleaseSetsAvailableUpdate() async throws {
        let release = try GitHubRelease(
            tag: "v1.5.0",
            htmlURL: #require(URL(string: "https://example.test/release/1.5.0"))
        )
        let harness = makeHarness(client: StaticReleaseClient(result: .success(release)))

        await harness.checker.checkNow()

        #expect(harness.model.availableUpdate == release)
        #expect(harness.prefs.latestUpdateTag == "v1.5.0")
        #expect(harness.prefs.latestUpdateURL?.absoluteString == "https://example.test/release/1.5.0")
        #expect(harness.prefs.lastUpdateCheckDate != nil)
    }

    @Test
    func sameVersionClearsAvailableUpdate() async throws {
        let release = try GitHubRelease(
            tag: "1.0.0",
            htmlURL: #require(URL(string: "https://example.test/release/1.0.0"))
        )
        let harness = makeHarness(client: StaticReleaseClient(result: .success(release)))
        harness.prefs.latestUpdateTag = "1.0.0"
        harness.prefs.latestUpdateURL = URL(string: "https://example.test/old")

        await harness.checker.checkNow()

        #expect(harness.model.availableUpdate == nil)
        #expect(harness.prefs.latestUpdateTag == nil)
        #expect(harness.prefs.latestUpdateURL == nil)
    }

    @Test
    func failureLeavesStateUnchanged() async {
        let harness = makeHarness(client: StaticReleaseClient(result: .failure(.unreachable)))
        harness.prefs.latestUpdateTag = "1.5.0"
        harness.prefs.latestUpdateURL = URL(string: "https://example.test/cached")
        harness.prefs.lastUpdateCheckDate = nil

        await harness.checker.checkNow()

        #expect(harness.prefs.lastUpdateCheckDate == nil)
        #expect(harness.prefs.latestUpdateTag == "1.5.0")
        #expect(harness.prefs.latestUpdateURL?.absoluteString == "https://example.test/cached")
    }

    @Test
    func hydrationSurfacesPreviouslyStoredUpdate() {
        let model = AppModel()
        let (prefs, _) = makePreferences()
        prefs.latestUpdateTag = "v9.9.9"
        prefs.latestUpdateURL = URL(string: "https://example.test/release/9.9.9")
        let client = StaticReleaseClient(result: .failure(.unreachable))

        _ = UpdateChecker(
            model: model,
            client: client,
            preferences: prefs,
            runningVersion: SemanticVersion(major: 1, minor: 0, patch: 0)
        )

        #expect(model.availableUpdate?.tag == "v9.9.9")
    }

    @Test
    func disabledToggleSkipsNetworkAndClearsStoredUpdate() async throws {
        let release = try GitHubRelease(
            tag: "v9.9.9",
            htmlURL: #require(URL(string: "https://example.test/x"))
        )
        let client = CountingReleaseClient(result: .success(release))
        let model = AppModel()
        let (prefs, _) = makePreferences()
        prefs.checkForUpdatesEnabled = false
        prefs.latestUpdateTag = "v9.9.9"
        prefs.latestUpdateURL = URL(string: "https://example.test/x")
        let checker = UpdateChecker(
            model: model,
            client: client,
            preferences: prefs,
            runningVersion: SemanticVersion(major: 1, minor: 0, patch: 0)
        )

        await checker.checkNow()

        let calls = await client.callCount
        #expect(calls == 0)
        #expect(prefs.latestUpdateTag == nil)
        #expect(prefs.latestUpdateURL == nil)
        #expect(model.availableUpdate == nil)
    }

    @Test
    func defaultsForCheckEnabledIsOn() {
        let (prefs, _) = makePreferences()
        #expect(prefs.checkForUpdatesEnabled == true)
    }

    @Test
    func startFiresLaunchTimeCheckEvenWithFreshLastDate() async throws {
        let release = try GitHubRelease(
            tag: "v1.5.0",
            htmlURL: #require(URL(string: "https://example.test/release/1.5.0"))
        )
        let client = CountingReleaseClient(result: .success(release))
        let model = AppModel()
        let (prefs, _) = makePreferences()
        // Last check 10 minutes ago: the normal 24h gate would skip,
        // but `start()` must force a launch-time check.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        prefs.lastUpdateCheckDate = now.addingTimeInterval(-10 * 60)
        let checker = UpdateChecker(
            model: model,
            client: client,
            preferences: prefs,
            runningVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
            wakeInterval: 24 * 60 * 60,
            now: { now }
        )

        checker.start()
        // Yield until the launch-time check completes (asserted via
        // CountingReleaseClient's call count incrementing).
        for _ in 0 ..< 100 {
            let calls = await client.callCount
            if calls >= 1 {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        checker.stop()

        let calls = await client.callCount
        #expect(calls == 1)
        #expect(model.availableUpdate == release)
        #expect(prefs.lastUpdateCheckDate == now)
    }

    @Test
    func hydrationDiscardsStaleStoredUpdateBelowRunningVersion() {
        let model = AppModel()
        let (prefs, _) = makePreferences()
        prefs.latestUpdateTag = "v1.0.0"
        prefs.latestUpdateURL = URL(string: "https://example.test/old")
        let client = StaticReleaseClient(result: .failure(.unreachable))

        _ = UpdateChecker(
            model: model,
            client: client,
            preferences: prefs,
            runningVersion: SemanticVersion(major: 2, minor: 0, patch: 0)
        )

        #expect(model.availableUpdate == nil)
        #expect(prefs.latestUpdateTag == nil)
    }
}

/// One-shot client that always returns the same scripted result.
private actor StaticReleaseClient: GitHubReleaseClient {
    private let result: Result<GitHubRelease, GitHubReleaseError>

    init(result: Result<GitHubRelease, GitHubReleaseError>) {
        self.result = result
    }

    func fetchLatestRelease() async -> Result<GitHubRelease, GitHubReleaseError> {
        result
    }
}

/// Records `fetchLatestRelease` invocations so tests can assert the
/// disabled-toggle path issues no network traffic.
private actor CountingReleaseClient: GitHubReleaseClient {
    private let result: Result<GitHubRelease, GitHubReleaseError>
    private(set) var callCount: Int = 0

    init(result: Result<GitHubRelease, GitHubReleaseError>) {
        self.result = result
    }

    func fetchLatestRelease() async -> Result<GitHubRelease, GitHubReleaseError> {
        callCount += 1
        return result
    }
}
