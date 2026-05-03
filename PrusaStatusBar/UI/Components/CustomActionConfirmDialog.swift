import AppKit
import SwiftUI

/// Native macOS confirmation for custom HTTP actions. Uses `NSAlert` so the
/// dialog matches every other system prompt (sheet positioning, button
/// metrics, focus ring, accessibility). The slot's SF Symbol is rendered
/// as the alert icon (tinted with the user's brand accent), the slot name
/// is the message, and `informativeText` is intentionally empty so the
/// HTTP method and URL never appear in this surface.
@MainActor
enum CustomActionConfirmPresenter {
    static func confirm(
        config: CustomActionConfig,
        accent: Theme.Accent,
        customAccentHex: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L10n.t("custom_action.untitled")
                : config.name
            alert.informativeText = ""
            alert.alertStyle = .informational

            if let icon = symbolIcon(for: config.symbol, accent: accent, customAccentHex: customAccentHex) {
                alert.icon = icon
            }

            alert.addButton(withTitle: L10n.t("actions.confirm.run"))
            alert.addButton(withTitle: L10n.t("common.cancel"))
            if config.method == .delete, let primary = alert.buttons.first {
                primary.hasDestructiveAction = true
            }

            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }

    /// Build a 64pt SF Symbol image tinted with the user's brand accent so
    /// the alert icon visually echoes the button the user just clicked.
    /// Falls back to `nil` (NSAlert keeps its default app icon) if the
    /// symbol name is empty or unavailable on this OS.
    private static func symbolIcon(
        for symbol: String,
        accent: Theme.Accent,
        customAccentHex: String
    ) -> NSImage? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "bolt" : trimmed
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let tint = NSColor(Theme.Palette.brand(accent, customHex: customAccentHex))
        let configuration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            .applying(.init(hierarchicalColor: tint))
        return base.withSymbolConfiguration(configuration) ?? base
    }
}
