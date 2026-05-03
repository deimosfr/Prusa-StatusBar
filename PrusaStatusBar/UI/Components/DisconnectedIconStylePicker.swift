import AppKit
import SwiftUI

/// Premium swatch-style picker for the disconnected menu-bar icon style.
/// Renders three cards in a single row, each previewing exactly what the
/// menu bar will show: the bundled `IconDisconnected` template, a tiny
/// minimal dot, and the user-chosen emoji. Tapping the already-selected
/// emoji card re-opens the macOS character palette so the user can change
/// the glyph without a separate text field.
struct DisconnectedIconStylePicker: View {
    @Binding var style: DisconnectedIconStyle
    let emoji: String
    let onPickEmoji: () -> Void

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    var body: some View {
        HStack(spacing: Theme.Spacing.sml) {
            cell(for: .default, helpKey: "menubar.disconnected_icon.style.default") {
                Image(StatusPresenter.AssetName.disconnected)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            cell(for: .minimal, helpKey: "menubar.disconnected_icon.style.minimal") {
                Circle()
                    .frame(width: 5, height: 5)
            }
            cell(for: .none, helpKey: "menubar.disconnected_icon.style.none") {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        Theme.Palette.textSecondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                    .frame(width: 14, height: 10)
            }
            cell(for: .emoji, helpKey: "menubar.disconnected_icon.style.emoji") {
                Text(emoji)
                    .font(.system(size: 14))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L10n.t("menubar.disconnected_icon.header")))
    }

    @ViewBuilder
    private func cell(
        for kind: DisconnectedIconStyle,
        helpKey: String,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        let isSelected = style == kind
        Button {
            if isSelected, kind == .emoji {
                onPickEmoji()
                return
            }
            style = kind
        } label: {
            content()
                .foregroundStyle(
                    isSelected ? Theme.Palette.brand(accent, customHex: customHex) : Theme.Palette.textSecondary
                )
                .frame(width: 28, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.Palette.brandMuted(accent, customHex: customHex) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Theme.Palette.brand(accent, customHex: customHex) : Theme.Palette.hairline,
                            lineWidth: isSelected ? 1.25 : 0.5
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(true)
        .help(helpTextFor(kind, helpKey: helpKey))
        .accessibilityLabel(L10n.t(helpKey))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func helpTextFor(_ kind: DisconnectedIconStyle, helpKey: String) -> String {
        if kind == .emoji, style == .emoji {
            return L10n.t("menubar.disconnected_icon.emoji.tooltip")
        }
        return L10n.t(helpKey)
    }
}

#if DEBUG
    private struct DisconnectedIconStylePickerPreview: View {
        @State private var style: DisconnectedIconStyle = .default
        @State private var emoji: String = "💤"
        var body: some View {
            DisconnectedIconStylePicker(
                style: $style,
                emoji: emoji,
                onPickEmoji: { emoji = "🛑" }
            )
            .padding()
            .frame(width: 320)
        }
    }

    #Preview {
        DisconnectedIconStylePickerPreview()
    }
#endif
