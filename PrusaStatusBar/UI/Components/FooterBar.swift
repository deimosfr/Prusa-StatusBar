import SwiftUI

/// Slim bottom row with two icon-only buttons: gear (Preferences, ⌘,) on
/// the leading edge and power (Quit, ⌘Q) on the trailing edge. When
/// `availableUpdate` is non-nil, a centered "New version available"
/// button in `Color("BrandGreen")` sits between them and opens the
/// GitHub release page on click. No surface fill or border, the chrome
/// blends into the popover background. Refresh lives in `HeroHeader`,
/// next to the "Updated Xs ago..." line, per
/// `openspec/specs/menu-bar-ui/spec.md`.
struct FooterBar: View {
    let onPreferences: () -> Void
    let onQuit: () -> Void
    var availableUpdate: GitHubRelease?
    var onOpenRelease: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            FooterIconButton(
                symbol: "gearshape",
                title: L10n.t("footer.preferences"),
                shortcutHint: "⌘,",
                action: onPreferences
            )
            .keyboardShortcut(",", modifiers: [.command])

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
    let shortcutHint: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

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
        .help("\(title) (\(shortcutHint))")
        .accessibilityLabel(Text("\(title) (\(shortcutHint))"))
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
