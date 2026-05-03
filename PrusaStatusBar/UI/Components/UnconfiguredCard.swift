import SwiftUI

/// Empty-state card shown in the dropdown when no printer is configured.
/// Headline + explanation copy + a primary button that opens Preferences on
/// the Printer tab via `onConfigure`.
struct UnconfiguredCard: View {
    let accent: Theme.Accent
    let customHex: String
    let onConfigure: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.med) {
            Image("PrusaCoreOne")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
            Text(L10n.t("dropdown.unconfigured.message"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onConfigure) {
                Text(L10n.t("dropdown.unconfigured.action"))
                    .font(.prusaBody.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sml)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.Palette.brand(accent, customHex: customHex))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .prusaCard()
    }
}
