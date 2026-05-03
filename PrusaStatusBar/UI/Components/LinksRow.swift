import SwiftUI

/// Compact action row above the footer offering quick links to PrusaLink
/// (the printer's own web UI) and PrusaConnect (Prusa's cloud dashboard).
/// Each button is disabled when its prerequisite setting is missing.
struct LinksRow: View {
    let prusaLinkVisible: Bool
    let prusaConnectVisible: Bool
    let prusaLinkEnabled: Bool
    let prusaLinkDisconnected: Bool
    let prusaConnectEnabled: Bool
    let onOpenPrusaLink: () -> Void
    let onOpenPrusaConnect: () -> Void

    private let rowHeight: CGFloat = 34

    init(
        prusaLinkVisible: Bool = true,
        prusaConnectVisible: Bool = true,
        prusaLinkEnabled: Bool,
        prusaLinkDisconnected: Bool = false,
        prusaConnectEnabled: Bool,
        onOpenPrusaLink: @escaping () -> Void,
        onOpenPrusaConnect: @escaping () -> Void
    ) {
        self.prusaLinkVisible = prusaLinkVisible
        self.prusaConnectVisible = prusaConnectVisible
        self.prusaLinkEnabled = prusaLinkEnabled
        self.prusaLinkDisconnected = prusaLinkDisconnected
        self.prusaConnectEnabled = prusaConnectEnabled
        self.onOpenPrusaLink = onOpenPrusaLink
        self.onOpenPrusaConnect = onOpenPrusaConnect
    }

    var body: some View {
        if prusaLinkVisible || prusaConnectVisible {
            HStack(spacing: 0) {
                if prusaLinkVisible {
                    LinkButton(
                        icon: .symbol("safari"),
                        title: "PrusaLink",
                        tooltipEnabled: L10n.t("links.prusalink.tooltip_enabled"),
                        tooltipDisabled: prusaLinkDisconnected
                            ? L10n.t("links.prusalink.tooltip_unreachable")
                            : L10n.t("links.prusalink.tooltip_unset"),
                        isEnabled: prusaLinkEnabled,
                        position: prusaConnectVisible ? .leading : .alone,
                        action: onOpenPrusaLink
                    )
                }

                if prusaLinkVisible, prusaConnectVisible {
                    divider
                }

                if prusaConnectVisible {
                    LinkButton(
                        icon: .asset("PrusaConnectIcon"),
                        title: "PrusaConnect",
                        tooltipEnabled: L10n.t("links.prusaconnect.tooltip_enabled"),
                        tooltipDisabled: L10n.t("links.prusaconnect.tooltip_unset"),
                        isEnabled: prusaConnectEnabled,
                        position: prusaLinkVisible ? .trailing : .alone,
                        action: onOpenPrusaConnect
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

    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: Theme.Hairline.width)
    }
}

enum LinkIcon: Equatable {
    case symbol(String)
    case asset(String)
}

private enum LinkButtonPosition {
    case leading
    case trailing
    case alone
}

private struct LinkButton: View {
    let icon: LinkIcon
    let title: String
    let tooltipEnabled: String
    let tooltipDisabled: String
    let isEnabled: Bool
    let position: LinkButtonPosition
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                iconView
                Text(title)
                    .font(.prusaCaptionStrong)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isEnabled && isHovering ? Theme.Palette.brandMuted(accent, customHex: customHex) : Color.clear,
            in: hoverShape
        )
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1.0 : 0.45)
        .disabled(!isEnabled)
        .help(isEnabled ? tooltipEnabled : tooltipDisabled)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .light))
                .symbolRenderingMode(.hierarchical)
        case let .asset(name):
            Image(name)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
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
        case .alone:
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: r,
                style: .continuous
            )
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return Theme.Palette.textSecondary
        }
        return isHovering ? Theme.Palette.brand(accent, customHex: customHex) : Theme.Palette.textPrimary
    }
}
