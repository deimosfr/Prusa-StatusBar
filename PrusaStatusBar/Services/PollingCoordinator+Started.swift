import Foundation

extension PollingCoordinator {
    /// Per-job dispatch for the "Print starting" notification.
    ///
    /// Fires once when the printer enters `.printing` from a non-active
    /// prelude state (`.idle`, `.ready`, `.busy`, or `.stopped`). Resuming
    /// from `.paused` is intentionally excluded: resuming a paused job is
    /// not a fresh start and the user should not get a banner every time
    /// they pause and resume mid-print. `.stopped` IS a valid prelude
    /// because the user can stop a job and immediately queue a new one.
    ///
    /// The latch resets when the state leaves `.printing`, so a subsequent
    /// fresh job (e.g. `.finished -> .idle -> .printing`) re-arms the
    /// notification.
    func dispatchStarted(
        previousState: PrinterState,
        currentState: PrinterState,
        jobKey: String
    ) async {
        let isFreshStart = currentState == .printing
            && (previousState == .idle
                || previousState == .ready
                || previousState == .busy
                || previousState == .stopped)
        if isFreshStart {
            if model.notifyOnStarted, notifiedStartedForJob != jobKey {
                notifiedStartedForJob = jobKey
                let body = model.lastJob?.displayName ?? L10n.t("notification.started.body_default")
                await notifier.deliver(
                    title: L10n.t("notification.started.title"),
                    body: body,
                    identifier: "started:\(jobKey)"
                )
            }
        } else if currentState != .printing {
            notifiedStartedForJob = nil
        }
    }
}
