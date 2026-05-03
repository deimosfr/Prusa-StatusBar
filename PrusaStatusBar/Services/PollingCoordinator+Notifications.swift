import Foundation

/// Per-state notification dispatch carved out of `PollingCoordinator` so
/// the main type stays under the `type_body_length` lint budget. All three
/// transitions (finished / attention / error) share the same image-
/// resolution helper which prefers a live camera snapshot over the cached
/// gcode thumbnail.
extension PollingCoordinator {
    func dispatchFinished(
        previousState: PrinterState,
        currentState: PrinterState,
        jobKey: String
    ) async {
        if previousState != .finished, currentState == .finished {
            if model.notifyOnFinished, notifiedFinishForJob != jobKey {
                notifiedFinishForJob = jobKey
                let body = model.lastJob?.displayName ?? L10n.t("notification.finished.body_default")
                let imageURL = await resolveNotificationImage(jobKey: jobKey)
                await notifier.deliver(
                    title: L10n.t("notification.finished.title"),
                    body: body,
                    identifier: "finished:\(jobKey)",
                    imageURL: imageURL
                )
            }
        } else if currentState != .finished {
            // Reset the latch as soon as we leave .finished.
            notifiedFinishForJob = nil
        }
    }

    func dispatchAttention(
        previousState: PrinterState,
        currentState: PrinterState,
        jobKey: String,
        printerName: String
    ) async {
        if previousState != .attention, currentState == .attention {
            if model.notifyOnAttention, notifiedAttentionForJob != jobKey {
                notifiedAttentionForJob = jobKey
                let imageURL = await resolveNotificationImage(jobKey: jobKey)
                await notifier.deliver(
                    title: L10n.t("notification.attention.title"),
                    body: String(format: L10n.t("notification.state_body"), printerName, currentState.rawValue),
                    identifier: "attention:\(jobKey)",
                    imageURL: imageURL
                )
            }
        } else if currentState != .attention {
            notifiedAttentionForJob = nil
        }
    }

    func dispatchError(
        previousState: PrinterState,
        currentState: PrinterState,
        jobKey: String,
        printerName: String
    ) async {
        if previousState != .error, currentState == .error {
            if model.notifyOnError, notifiedErrorForJob != jobKey {
                notifiedErrorForJob = jobKey
                let imageURL = await resolveNotificationImage(jobKey: jobKey)
                await notifier.deliver(
                    title: L10n.t("notification.error.title"),
                    body: String(format: L10n.t("notification.state_body"), printerName, currentState.rawValue),
                    identifier: "error:\(jobKey)",
                    imageURL: imageURL
                )
            }
        } else if currentState != .error {
            notifiedErrorForJob = nil
        }
    }

    /// Pick the best image to attach to a state-transition notification.
    /// Tries a live camera snapshot first (Buddy preferred over Generic, see
    /// `CameraSnapshotService`); falls back to the cached gcode thumbnail
    /// when no camera is configured, every provider fails, or the budget
    /// elapses. Returns `nil` if neither is available, in which case the
    /// notification ships text-only.
    ///
    /// Snapshots are cached per `jobKey` so the second and third state
    /// transition for the same job (e.g. `attention -> error -> finished`)
    /// reuse the JPEG bytes captured the first time. Only the temp file is
    /// rewritten because `UNUserNotificationCenter.add(_:)` takes ownership
    /// of the attachment URL.
    private func resolveNotificationImage(jobKey: String) async -> URL? {
        if cachedSnapshotJobKey != jobKey {
            cachedSnapshotJobKey = jobKey
            cachedSnapshotData = nil
        }
        if cachedSnapshotData == nil {
            cachedSnapshotData = await snapshotService.captureForNotification()
        }
        if let snapshot = cachedSnapshotData {
            if let url = NotificationImage.writeTemp(data: snapshot, suggestedExtension: "jpg") {
                return url
            }
        }
        return model.lastThumbnail.flatMap { NotificationImage.writeTemp(data: $0) }
    }
}
