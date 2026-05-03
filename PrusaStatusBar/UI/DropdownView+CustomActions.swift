import SwiftUI

/// Custom-action wiring carved out of `DropdownView` so the main struct
/// stays under the lint budget. These helpers translate the slot
/// configurations on `AppModel` into per-slot visibility decisions and
/// drive the local in-flight + success/failure feedback state.
extension DropdownView {
    func customConfig(_ slot: CustomActionSlot) -> CustomActionConfig {
        model.customActions[slot] ?? .default
    }

    func isCustomVisible(_ slot: CustomActionSlot) -> Bool {
        isCustomActionVisible(
            customConfig(slot),
            isDisconnected: model.isDisconnected,
            isUnconfigured: !model.isConfigured
        )
    }

    var hasVisibleCustomActionsRow: Bool {
        isCustomVisible(.rowLeft) || isCustomVisible(.rowRight)
    }

    var hasVisibleSecondCustomActionsRow: Bool {
        isCustomVisible(.rowSecondLeft) || isCustomVisible(.rowSecondRight)
    }

    /// Sets the feedback to `.running`, awaits the runner, then flashes a
    /// success or failure indicator for ~600ms before reverting to
    /// `.idle`. Multiple rapid clicks coalesce because the button is
    /// disabled while running.
    func runCustomAction(_ slot: CustomActionSlot) {
        let current = customActionFeedback[slot] ?? .idle
        guard current != .running else { return }
        customActionFeedback[slot] = .running
        Task {
            let outcome = await onRunCustomAction(slot)
            await MainActor.run {
                customActionFeedback[slot] = Self.feedback(for: outcome)
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                if customActionFeedback[slot] != .running {
                    customActionFeedback[slot] = .idle
                }
            }
        }
    }

    static func feedback(
        for outcome: Result<CustomActionRunOutcome, CustomActionError>
    ) -> CustomActionFeedback {
        switch outcome {
        case let .success(value) where value.isSuccess: .success
        case .success, .failure: .failure
        }
    }
}
