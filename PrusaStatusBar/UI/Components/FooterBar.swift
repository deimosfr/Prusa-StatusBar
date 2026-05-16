import SwiftUI

/// Slim bottom row with icon-only buttons: gear (Preferences, ⌘,) on the
/// leading edge followed immediately by the optional detach button, then
/// a centered "New version available" callout when an update is available,
/// and power (Quit, ⌘Q) on the trailing edge. No surface fill or border --
/// the chrome blends into the popover background. Refresh lives in
/// `HeroHeader`, per `openspec/specs/menu-bar-ui/spec.md`.
struct FooterBar: View {
    let onPreferences: () -> Void
    let onQuit: () -> Void
    var availableUpdate: GitHubRelease?
    var onOpenRelease: () -> Void = {}
    /// When non-nil, shows a "Detach to window" button immediately after the
    /// Preferences button. Pass `nil` inside the detached window itself.
    var onDetach: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            FooterIconButton(
                symbol: "gearshape",
                title: L10n.t("footer.preferences"),
                shortcutHint: "⌘,",
                action: onPreferences
            )
            .keyboardShortcut(",", modifiers: [.command])

            if let onDetach {
                FooterIconButton(
                    symbol: "pip.enter",
                    title: L10n.t("footer.detach"),
                    shortcutHint: nil,
                    action: onDetach
                )
            }

            Spacer(minLength: 0)

            if availableUpdate != nil {
                UpdateCallout(action: onOpenRelease)
                Spacer(minLength: 0)
            }

            FooterIconButton(
                symbol: "power",
                title: L10n.t("footer.quit"),
                shortcutHint: "⌘Q",
                action: onQuit
            )
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}

private struct FooterIconButton: View {
    let symbol: String
    let title: String
    var shortcutHint: String?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    private var helpText: String {
        if let shortcutHint, !shortcutHint.isEmpty {
            return "\(title) (\(shortcutHint))"
        }
        return title
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? Theme.Palette.brand(accent, customHex: customHex) : Theme.Palette.textSecondary)
        .help(helpText)
        .accessibilityLabel(Text(helpText))
        .onHover { isHovering = $0 }
    }
}

private struct UpdateCallout: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(L10n.t("footer.update.available"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color("BrandGreen"))
                .underline(isHovering, color: Color("BrandGreen"))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("footer.update.available"))
        .accessibilityLabel(Text(L10n.t("footer.update.available")))
        .onHover { isHovering = $0 }
    }
}
