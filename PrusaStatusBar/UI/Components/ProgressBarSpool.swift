import SwiftUI

/// Spool-themed capsule progress bar. Shares the public surface and the
/// floating percent chip with `ProgressBarPremium`, but the leading-edge
/// marker is the Prusa filament spool wheel rather than a glow dot.
///
/// The spool body rotates as the print advances (driven directly by
/// `value`, so it spins multiple turns over the course of a job) while
/// the filament ring drains from full to empty: the visual metaphor is
/// "filament being spent into the print".
struct ProgressBarSpool: View {
    /// Normalized 0...1.
    let value: Double
    /// Whether to render the percent label above the bar. Default `true`.
    let showsPercent: Bool
    /// Bumped by the host whenever the bar should restart its animated
    /// decorations. Defaults to `0`.
    let resetToken: Int

    init(value: Double, showsPercent: Bool = true, resetToken: Int = 0) {
        self.value = value
        self.showsPercent = showsPercent
        self.resetToken = resetToken
    }

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex
    @State private var chipWidth: CGFloat = 0

    private static let spoolSize: CGFloat = 22
    private static let tooltipHalfWidth: CGFloat = 24
    private static let tooltipHeight: CGFloat = 18
    /// Total turns the spool body rotates from 0% to 100%. Four full
    /// turns reads as a clearly spinning wheel during the slow real-time
    /// progress changes a printer reports, without becoming dizzying in
    /// the side-by-side preview.
    private static let totalSpins: Double = 4

    private var clamped: Double {
        max(0, min(1, value))
    }

    private var percentText: String {
        "\(Int((clamped * 100).rounded()))%"
    }

    var body: some View {
        Group {
            if showsPercent {
                VStack(spacing: 2) {
                    tooltipRow
                    bar
                }
            } else {
                bar
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.t("a11y.progress_bar"))
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = max(geo.size.height, Self.spoolSize)
            // Spool's center can only travel between `inset` and
            // `width - inset` because half a spool always hangs off each
            // edge. Render the track only over that reachable span so
            // the bar does not show stretches the spool can never reach.
            let inset = Self.spoolSize / 2
            let usable = max(width - Self.spoolSize, 1)
            let spoolCenterX = inset + clamped * usable
            // Fill's leading edge sits at the start of the usable track;
            // its trailing edge sits a short way past the spool's middle
            // so the bar visually tucks under the spool body rather than
            // stopping right at the spool's centerline.
            let fillTuck: CGFloat = 5
            let fillWidth = min(usable, max(0, spoolCenterX - inset + fillTuck))

            ZStack(alignment: .leading) {
                trackWithFill(usableWidth: usable, fillWidth: fillWidth)
                    .frame(width: usable, height: Theme.Layout.progressBarHeight)
                    .position(x: width / 2, y: height / 2)
                    .animation(
                        .spring(response: 1.1, dampingFraction: 0.78),
                        value: clamped
                    )

                SpoolThumb(
                    fillProgress: clamped,
                    bodyRotationDegrees: clamped * 360 * Self.totalSpins,
                    filamentColor: Theme.Palette.brand(accent, customHex: customHex)
                )
                .frame(width: Self.spoolSize, height: Self.spoolSize)
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                .position(x: spoolCenterX, y: height / 2)
                .animation(
                    .spring(response: 1.1, dampingFraction: 0.78),
                    value: clamped
                )
            }
        }
        .frame(height: max(Self.spoolSize, Theme.Layout.progressBarHeight))
    }

    private var tooltipRow: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let inset = Self.spoolSize / 2
            let usable = max(width - Self.spoolSize, 1)
            let spoolCenterX = inset + clamped * usable
            // Clamp the chip's trailing edge to the bar's trailing edge
            // so a wide label like "100%" never escapes the card. Leading
            // side is left alone: the spool's own inset already keeps
            // the chip visually anchored at low percentages.
            let chipX = min(width - chipWidth / 2, spoolCenterX)
            AnimatedPercentChip(value: clamped, accent: accent, customHex: customHex)
                .position(x: chipX, y: Self.tooltipHeight / 2)
                .animation(
                    .spring(response: 1.1, dampingFraction: 0.78),
                    value: clamped
                )
        }
        .frame(height: Self.tooltipHeight)
        .onPreferenceChange(AnimatedPercentChipWidthKey.self) { newValue in
            Task { @MainActor in
                chipWidth = newValue
            }
        }
    }

    /// Track + fill, rendered as a rectangular fill on top of a muted
    /// background, both clipped to a Capsule. The capsule clip rounds
    /// the track's outer ends but leaves the fill's trailing edge
    /// straight, so the fill always ends exactly under the spool's
    /// middle with no rounded-corner gap.
    private func trackWithFill(usableWidth: CGFloat, fillWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Theme.Palette.brandMuted(accent, customHex: customHex)

            if fillWidth > 0.5 {
                LinearGradient(
                    colors: [
                        Theme.Palette.brand(accent, customHex: customHex).opacity(0.92),
                        Theme.Palette.brand(accent, customHex: customHex)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fillWidth)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                    .frame(width: fillWidth)
                )
            }
        }
        .frame(width: usableWidth)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 18) {
            ProgressBarSpool(value: 0)
            ProgressBarSpool(value: 0.04)
            ProgressBarSpool(value: 0.18)
            ProgressBarSpool(value: 0.62)
            ProgressBarSpool(value: 0.92)
            ProgressBarSpool(value: 1.0)
            ProgressBarSpool(value: 0.62, showsPercent: false)
        }
        .padding()
        .frame(width: 320)
    }
#endif
