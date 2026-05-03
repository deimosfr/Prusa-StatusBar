import AppKit
import Foundation

/// Custom-action invocation pulled out of `MenuBarController` so the
/// host class stays under the lint budget. Resolves the slot config,
/// optionally shows a SwiftUI confirmation card via
/// `CustomActionConfirmPresenter`, fires the HTTP request, and surfaces
/// failures via the existing notification pipeline. Success is silent on
/// purpose to avoid notification fatigue when buttons are used routinely.
extension MenuBarController {
    func runCustomAction(
        _ slot: CustomActionSlot
    ) async -> Result<CustomActionRunOutcome, CustomActionError> {
        guard let config = model.customActions[slot], config.enabled else {
            return .failure(.slotMissingConfig)
        }
        if config.confirmBeforeRun {
            let confirmed = await confirmCustomAction(config)
            guard confirmed else { return .failure(.slotMissingConfig) }
        }
        let outcome = await customActionRunner.run(config)
        switch outcome {
        case let .success(value) where !value.isSuccess:
            await notifyCustomActionFailure(config: config, message: "HTTP \(value.httpStatus)")
        case let .failure(error):
            await notifyCustomActionFailure(config: config, message: error.displayDescription)
        case .success:
            break
        }
        return outcome
    }

    private func confirmCustomAction(_ config: CustomActionConfig) async -> Bool {
        await CustomActionConfirmPresenter.confirm(
            config: config,
            accent: model.accent,
            customAccentHex: model.customAccentHex
        )
    }

    private func notifyCustomActionFailure(config: CustomActionConfig, message: String) async {
        let actionName = config.name.isEmpty ? L10n.t("custom_action.untitled") : config.name
        let title = String(format: L10n.t("actions.notification.failure_title"), actionName)
        let body = String(message.prefix(120))
        await notifier.deliver(
            title: title,
            body: body,
            identifier: "custom-action.\(actionName).failure"
        )
    }
}
