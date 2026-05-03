import SwiftUI

/// Optional row of two icon + text custom action buttons inserted between
/// `LinksRow` and `FooterBar`. Mirrors `LinksRow` styling (rounded card,
/// hairline border). Collapses gracefully:
///   - 0 visible -> the row is not rendered (caller handles this).
///   - 1 visible -> the visible button spans the full row width.
///   - 2 visible -> two-column row with hairline divider.
struct CustomActionsRow: View {
    let leftConfig: CustomActionConfig
    let rightConfig: CustomActionConfig
    let leftVisible: Bool
    let rightVisible: Bool
    let leftFeedback: CustomActionFeedback
    let rightFeedback: CustomActionFeedback
    let onRunLeft: () -> Void
    let onRunRight: () -> Void

    private let rowHeight: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            if leftVisible {
                CustomActionRowButton(
                    config: leftConfig,
                    feedback: leftFeedback,
                    position: rightVisible ? .leading : .full,
                    action: onRunLeft
                )
            }
            if leftVisible, rightVisible {
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(width: Theme.Hairline.width)
            }
            if rightVisible {
                CustomActionRowButton(
                    config: rightConfig,
                    feedback: rightFeedback,
                    position: leftVisible ? .trailing : .full,
                    action: onRunRight
                )
            }
        }
        .frame(height: rowHeight)
        .background(
            Theme.Palette.surfaceElevated,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

private enum CustomActionRowButtonPosition {
    case leading
    case trailing
    case full
}

private struct CustomActionRowButton: View {
    let config: CustomActionConfig
    let feedback: CustomActionFeedback
    let position: CustomActionRowButtonPosition
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                iconView
                Text(displayName)
                    .font(.prusaCaptionStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isHovering ? Theme.Palette.brandMuted(accent, customHex: customHex) : Color.clear,
            in: hoverShape
        )
        .foregroundStyle(foreground)
        .help(displayName)
        .accessibilityLabel(Text(displayName))
        .onHover { isHovering = $0 }
        .disabled(feedback == .running)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: feedback)
    }

    private var displayName: String {
        config.name.isEmpty ? L10n.t("custom_action.untitled") : config.name
    }

    @ViewBuilder
    private var iconView: some View {
        switch feedback {
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 14, height: 14)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 14, height: 14)
        case .idle:
            Image(systemName: config.symbol.isEmpty ? "bolt" : config.symbol)
                .font(.system(size: 12, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 14, height: 14)
        }
    }

    private var hoverShape: UnevenRoundedRectangle {
        let r = Theme.Radius.card
        switch position {
        case .leading:
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .trailing:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: r,
                topTrailingRadius: r,
                style: .continuous
            )
        case .full:
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: r,
                style: .continuous
            )
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
                : Theme.Palette.textPrimary
        }
    }
}
