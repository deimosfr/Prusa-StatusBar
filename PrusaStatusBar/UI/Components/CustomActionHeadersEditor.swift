import SwiftUI

/// Repeating editor for the per-slot HTTP header list. Each row uses a
/// two-line layout (Key + Value stacked) with a leading colored
/// capsule + matching tinted background so neighbouring header pairs
/// stay visually distinct. The example placeholders
/// (`e.g. Authorization`, `e.g. Bearer xxx`) live as dimmed text
/// inside the fields via `PlainBorderedTextField`. The header value
/// row defaults to a `SecureField` with a per-row eye toggle so a
/// Bearer token does not sit in plaintext on screen unless requested.
struct CustomActionHeadersEditor: View {
    @Binding var headers: [CustomActionHeader]
    @Binding var revealedHeaderValues: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            if headers.isEmpty {
                Text(L10n.t("prefs.actions.headers.empty"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(headers.enumerated()), id: \.element.id) { index, header in
                        HeaderRow(
                            header: bindingForHeader(at: index),
                            tint: Self.palette[index % Self.palette.count],
                            isRevealed: bindingForReveal(of: header.id),
                            onRemove: { remove(id: header.id) }
                        )
                    }
                }
            }
        }
    }

    /// Distinct hue per header pair. Cycles through a small,
    /// hand-picked palette so neighbouring rows never share a tint.
    /// Independent of the user-selected brand accent so the rows stay
    /// readable on every theme.
    static let palette: [Color] = [
        Color(red: 0.36, green: 0.78, blue: 0.45), // green
        Color(red: 0.34, green: 0.62, blue: 0.94), // blue
        Color(red: 0.95, green: 0.61, blue: 0.27), // orange
        Color(red: 0.78, green: 0.46, blue: 0.93), // purple
        Color(red: 0.95, green: 0.40, blue: 0.55), // pink
        Color(red: 0.27, green: 0.78, blue: 0.78) // teal
    ]

    private var sectionHeader: some View {
        HStack {
            Text(L10n.t("prefs.actions.field.headers"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Button {
                headers.append(CustomActionHeader())
            } label: {
                Label(L10n.t("prefs.actions.headers.add"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func bindingForHeader(at index: Int) -> Binding<CustomActionHeader> {
        Binding(
            get: { headers[index] },
            set: { headers[index] = $0 }
        )
    }

    private func remove(id: UUID) {
        headers.removeAll { $0.id == id }
        revealedHeaderValues.remove(id)
    }

    private func bindingForReveal(of id: UUID) -> Binding<Bool> {
        Binding(
            get: { revealedHeaderValues.contains(id) },
            set: { reveal in
                if reveal {
                    revealedHeaderValues.insert(id)
                } else {
                    revealedHeaderValues.remove(id)
                }
            }
        )
    }
}

private struct HeaderRow: View {
    @Binding var header: CustomActionHeader
    let tint: Color
    @Binding var isRevealed: Bool
    let onRemove: () -> Void

    private let labelColumnWidth: CGFloat = 44
    private let fieldHeight: CGFloat = 26
    private let interFieldSpacing: CGFloat = 6
    /// Locked row height so the leading capsule never resizes when
    /// rows are added or removed. Matches `2 * fieldHeight + interFieldSpacing`.
    private var contentHeight: CGFloat {
        fieldHeight * 2 + interFieldSpacing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(tint)
                .frame(width: 4, height: contentHeight)

            VStack(alignment: .leading, spacing: interFieldSpacing) {
                keyRow
                valueRow
            }
            .frame(height: contentHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isRevealed
                    ? L10n.t("prefs.actions.headers.hide_value")
                    : L10n.t("prefs.actions.headers.show_value"))

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("prefs.actions.headers.remove"))
            }
            .frame(height: contentHeight)
        }
        .frame(height: contentHeight)
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .background(
            tint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var keyRow: some View {
        HStack(spacing: 8) {
            Text(L10n.t("prefs.actions.headers.key_label"))
                .font(.prusaCaption)
                .foregroundStyle(tint)
                .frame(width: labelColumnWidth, alignment: .leading)
            PlainBorderedTextField(
                placeholder: L10n.t("prefs.actions.headers.name_example"),
                text: $header.name
            )
            .frame(height: fieldHeight)
        }
    }

    private var valueRow: some View {
        HStack(spacing: 8) {
            Text(L10n.t("prefs.actions.headers.value_label"))
                .font(.prusaCaption)
                .foregroundStyle(tint)
                .frame(width: labelColumnWidth, alignment: .leading)
            PlainBorderedTextField(
                placeholder: L10n.t("prefs.actions.headers.value_example"),
                text: $header.value,
                isSecure: !isRevealed
            )
            .frame(height: fieldHeight)
        }
    }
}
