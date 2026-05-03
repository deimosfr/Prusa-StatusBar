import SwiftUI

/// Local feedback states a custom action button can be in. Driven by the
/// host view via `@State`; the runner notifies completion through a
/// `Task` callback owned by the parent.
public enum CustomActionFeedback: Equatable, Sendable {
    case idle
    case running
    case success
    case failure
}

/// Icon-only header slot button. Mirrors the visual treatment of
/// `FooterIconButton` (Quit), with the addition of in-flight + result
/// feedback states. Reserves a fixed 32pt width so the centered title
/// stays centered whether or not this button is visible.
struct CustomActionIconButton: View {
    let config: CustomActionConfig
    let feedback: CustomActionFeedback
    let isVisible: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isVisible {
                visibleButton
            } else {
                Color.clear
                    .frame(width: 32, height: 28)
            }
        }
    }

    private var visibleButton: some View {
        Button(action: action) {
            content
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
        .disabled(feedback == .running)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: feedback)
    }

    @ViewBuilder
    private var content: some View {
        switch feedback {
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.hierarchical)
        case .idle:
            Image(systemName: resolvedSymbolName)
                .font(.system(size: 16, weight: .light))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var resolvedSymbolName: String {
        config.symbol.isEmpty ? "bolt" : config.symbol
    }

    private var tooltip: String {
        let base = config.name.isEmpty ? L10n.t("custom_action.untitled") : config.name
        switch config.visibility {
        case .always:
            return base
        case .whenConnected:
            return "\(base) (\(L10n.t("prefs.actions.visibility.when_connected")))"
        case .whenDisconnected:
            return "\(base) (\(L10n.t("prefs.actions.visibility.when_disconnected")))"
        }
    }

    private var foreground: Color {
        switch feedback {
        case .failure: Theme.Palette.stateAmber
        case .success: Theme.Palette.brand(accent, customHex: customHex)
        case .running: Theme.Palette.textSecondary
        case .idle:
            isHovering
                ? Theme.Palette.brand(accent, customHex: customHex)
                : Theme.Palette.textSecondary
        }
    }
}
