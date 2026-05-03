import AppKit
import Foundation

/// Drives the polling loop on the main actor. Owns one `Task` at a time so
/// stop/start is cheap and the cadence can be retuned without races.
///
/// Spec reference: `openspec/specs/polling/spec.md`.
@MainActor
public final class PollingCoordinator {
    /// Internal (not private) so cross-file extensions like
    /// `PollingCoordinator+Started.swift` can read the dispatch context.
    let model: AppModel
    private let client: PrusaLinkClient
    let notifier: NotificationService
    let snapshotService: CameraSnapshotService

    private var loopTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private var previousState: PrinterState?
    /// Latches for per-state notifications. Internal (not private) so cross-
    /// file extensions like `PollingCoordinator+Started.swift` and
    /// `PollingCoordinator+Notifications.swift` see the same instances as
    /// the main dispatch loop.
    var notifiedStartedForJob: String?
    var notifiedFinishForJob: String?
    var notifiedAttentionForJob: String?
    var notifiedErrorForJob: String?

    /// Camera snapshot cache scoped to a single job. Capturing a snapshot
    /// hits an RTSP probe + frame grab + JPEG encode (up to 8s); a job that
    /// transitions through `attention -> error -> finished` would pay that
    /// cost three times. We cache the JPEG bytes per `jobKey` and re-write
    /// only the temp file (the system takes ownership of attachment URLs
    /// at delivery, so reusing the same URL across notifications is unsafe).
    var cachedSnapshotJobKey: String?
    var cachedSnapshotData: Data?

    public init(
        model: AppModel,
        client: PrusaLinkClient,
        notifier: NotificationService,
        snapshotService: CameraSnapshotService = StubCameraSnapshotService()
    ) {
        self.model = model
        self.client = client
        self.notifier = notifier
        self.snapshotService = snapshotService
    }

    public func start() {
        guard loopTask == nil else { return }
        observeSleepWake()
        loopTask = Task { [weak self] in
            await self?.run()
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        if let token = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let token = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        sleepObserver = nil
        wakeObserver = nil
    }

    /// Out-of-band single refresh. Used by "Refresh now" and dropdown-open.
    public func refreshNow() {
        Task { [weak self] in
            await self?.refreshOnce()
        }
    }

    // MARK: - Loop

    private func run() async {
        while !Task.isCancelled {
            await refreshOnce()
            let interval = computeNextInterval()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// Bumps `AppModel.printingBurstToken` on every transition into
    /// `.printing` from a non-printing prelude (`.idle`, `.ready`, `.busy`,
    /// `.stopped`, `.paused`). The `MenuBarController` observes the token
    /// and plays the bounded 2-cycle "started printing" animation on the
    /// status item.
    ///
    /// Distinct from `dispatchStarted` (per-job started-notification latch)
    /// which excludes `paused -> printing`; the burst includes it because
    /// users want a visual cue that the printer just resumed.
    ///
    /// Internal (not private) so transition coverage lives in
    /// `PollingCoordinatorTransitionTests` without spinning a real polling
    /// loop. `previous == nil` means "no prior observation" (first poll
    /// after launch); the burst is suppressed there because the
    /// launch-while-printing case is handled by `MenuBarController` via
    /// `didPlayLaunchAnimation`.
    func bumpPrintingBurstToken(previous: PrinterState?, current: PrinterState) {
        guard let previous else { return }
        guard previous != .printing, current == .printing else { return }
        model.printingBurstToken &+= 1
    }

    /// Visible to tests via `@testable import` so the dual-interval branch
    /// can be asserted without spinning the loop.
    func computeNextInterval() -> TimeInterval {
        // Two user-configurable intervals. Clamped on read by `UserPreferences`,
        // and again here so the model's mirror cannot accidentally outrun the
        // bounds. The disconnected branch kicks in only after the
        // `isDisconnected` threshold has been crossed (>= 2 consecutive
        // `.unreachable` failures), matching the menu-bar's disconnected
        // affordance.
        if model.isDisconnected {
            let raw = model.disconnectedRefreshIntervalSeconds
            let bounded = max(
                UserPreferences.disconnectedRefreshIntervalMin,
                min(UserPreferences.disconnectedRefreshIntervalMax, raw)
            )
            return TimeInterval(bounded)
        }
        let raw = model.refreshIntervalSeconds
        let bounded = max(UserPreferences.refreshIntervalMin, min(UserPreferences.refreshIntervalMax, raw))
        return TimeInterval(bounded)
    }

    private func refreshOnce() async {
        guard model.isConfigured else {
            return
        }
        model.isRefreshing = true
        defer { model.isRefreshing = false }

        let result = await client.fetchStatus()
        switch result {
        case let .success(status):
            var enriched = status
            if model.showFilamentType {
                enriched.activeFilamentMaterial = await fetchFilamentMaterial()
            }
            await applyStatus(enriched)
            model.lastError = nil
            model.consecutiveFailures = 0
            model.lastUpdate = Date()
            await refreshPrinterInfoIfNeeded()
        case let .failure(error):
            model.lastError = error
            model.consecutiveFailures += 1
            Log.polling.error("Status fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lazily fetch /api/v1/info once per session so the dropdown can show
    /// the printer's name and nozzle diameter. Cheap call, kept out of the
    /// hot status path so a stale info payload never blocks a status update.
    private func refreshPrinterInfoIfNeeded() async {
        guard model.printerInfo == nil else { return }
        let result = await client.fetchInfo()
        if case let .success(info) = result {
            model.printerInfo = info
        }
    }

    private func applyStatus(_ status: PrinterStatus) async {
        let previous = previousState
        let prevJobName = model.lastJob?.displayName

        // Drive job/thumbnail refresh while a job is active, and on the
        // finished state so the popover can show the just-completed file when
        // it opens cold. PrusaLink can drop `/api/v1/job` to 204 once the
        // print finishes, so on `.finished` we preserve any cached job rather
        // than clearing it on a nil response.
        if status.state.isActive {
            await refreshJobIfNeeded(previousFileName: prevJobName, clearWhenAbsent: true)
        } else if status.state == .finished {
            await refreshJobIfNeeded(previousFileName: prevJobName, clearWhenAbsent: false)
        } else if status.state == .idle || status.state == .ready {
            // Drop the cached job when we're back to idle so the next active
            // print refetches the file detail / thumbnail.
            model.lastJob = nil
            model.lastThumbnail = nil
        }

        if model.lastStatus != status {
            model.lastStatus = status
        }

        bumpPrintingBurstToken(previous: previous, current: status.state)

        await dispatchNotifications(previousState: previous, currentStatus: status)
        previousState = status.state
    }

    private func refreshJobIfNeeded(previousFileName: String?, clearWhenAbsent: Bool) async {
        let result = await client.fetchJob()
        switch result {
        case let .success(job):
            guard let job else {
                if clearWhenAbsent {
                    model.lastJob = nil
                    model.lastThumbnail = nil
                }
                return
            }
            // Only download the thumbnail when the file changed.
            let isSameFile = job.displayName == previousFileName
            model.lastJob = job
            if !isSameFile {
                model.lastThumbnail = nil
                if let path = job.thumbnailPath {
                    let thumbResult = await client.fetchThumbnail(at: path)
                    if case let .success(data) = thumbResult {
                        model.lastThumbnail = data
                    }
                }
            }
        case let .failure(error):
            Log.polling.notice("Job fetch failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func dispatchNotifications(previousState: PrinterState?, currentStatus: PrinterStatus) async {
        guard model.notificationsEnabled else { return }
        guard let previousState else { return }

        let jobKey = model.lastJob?.displayName ?? "no-file"
        let printerName = model.printerInfo?.name ?? "Your printer"

        await dispatchStarted(previousState: previousState, currentState: currentStatus.state, jobKey: jobKey)
        await dispatchFinished(previousState: previousState, currentState: currentStatus.state, jobKey: jobKey)
        await dispatchAttention(
            previousState: previousState,
            currentState: currentStatus.state,
            jobKey: jobKey,
            printerName: printerName
        )
        await dispatchError(
            previousState: previousState,
            currentState: currentStatus.state,
            jobKey: jobKey,
            printerName: printerName
        )
    }

    // MARK: - Sleep / wake

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSleep()
            }
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
    }

    private func handleSleep() {
        Log.polling.info("System sleep, pausing polling")
        loopTask?.cancel()
        loopTask = nil
    }

    private func handleWake() {
        Log.polling.info("System wake, resuming polling")
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.run()
        }
    }
}

// MARK: - Filament

private extension PollingCoordinator {
    /// Hits the legacy `/api/printer` endpoint for `telemetry.material`. The
    /// modern `/api/v1/status` does not include the loaded filament on most
    /// firmware (MK3.5, MK4, MK4S, Core One), so this matches the path the
    /// Home Assistant PrusaLink integration takes. Failures are logged but
    /// do not break the surrounding status update; the row simply stays
    /// hidden until the next successful fetch.
    func fetchFilamentMaterial() async -> String? {
        let result = await client.fetchLegacyMaterial()
        switch result {
        case let .success(material):
            return material
        case let .failure(error):
            Log.polling.notice(
                "Legacy material fetch failed (non-fatal): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

// MARK: - Job actions

public extension PollingCoordinator {
    /// Send a Resume command for the cached job, then refresh status so the
    /// UI can re-evaluate the action buttons against the new state.
    func resumeCurrentJob() {
        runJobAction(label: "resume") { [client] id in await client.resumeJob(id: id) }
    }

    /// Send a Pause command for the cached job, then refresh status.
    func pauseCurrentJob() {
        runJobAction(label: "pause") { [client] id in await client.pauseJob(id: id) }
    }

    /// Send a Stop (cancel) command for the cached job, then refresh status.
    func stopCurrentJob() {
        runJobAction(label: "stop") { [client] id in await client.stopJob(id: id) }
    }

    private func runJobAction(
        label: String,
        action: @escaping @Sendable (Int) async -> Result<Void, PrusaLinkError>
    ) {
        guard let id = model.lastJob?.id else {
            Log.polling.notice("Job action \(label, privacy: .public) skipped: no cached job id")
            return
        }
        Task { [weak self] in
            let result = await action(id)
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success:
                    self.refreshNow()
                case let .failure(error):
                    Log.polling.error(
                        "Job \(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}
