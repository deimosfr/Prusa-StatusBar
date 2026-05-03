import SwiftUI

/// Premium capsule progress bar with floating percent chip, gradient fill,
/// inner highlight, and an animated sheen sweep.
///
/// The sheen sweep runs for a bounded number of cycles per `resetToken`
/// change (per spec: 3 cycles per dropdown open), then freezes. The
/// capsule fill width keeps animating in response to `value` changes.
struct ProgressBarPremium: View {
    /// Normalized 0...1.
    let value: Double
    /// Whether to render the percent label inside the bar. Default `true`.
    let showsPercent: Bool
    /// Bumped by the host whenever the bar should restart its sheen
    /// sweep. Defaults to `0` so previews and isolated callers still
    /// get the on-load animation.
    let resetToken: Int
    /// When false (popover hidden), the sheen `TimelineView` is swapped for
    /// a static `Color.clear` so the 30fps schedule does not keep firing
    /// while the dropdown is offscreen.
    let isPopoverVisible: Bool

    init(value: Double, showsPercent: Bool = true, resetToken: Int = 0, isPopoverVisible: Bool = true) {
        self.value = value
        self.showsPercent = showsPercent
        self.resetToken = resetToken
        self.isPopoverVisible = isPopoverVisible
    }

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    /// Number of sheen cycles that play after each `resetToken` change
    /// before the decoration freezes.
    private static let animatedCycleCount: Double = 3
    private static let sheenCycleSeconds: Double = 1.8

    @State private var sessionStart: Date = .init()
    @State private var chipWidth: CGFloat = 0

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
        .onChange(of: resetToken) { _, _ in
            sessionStart = .init()
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let fillWidth = max(0, clamped * width)

            trackWithFill(totalWidth: width, fillWidth: fillWidth)
                .frame(width: width, height: height)
                .animation(
                    .spring(response: 1.1, dampingFraction: 0.78),
                    value: clamped
                )
        }
        .frame(height: Theme.Layout.progressBarHeight)
    }

    private var tooltipRow: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rawX = clamped * width
            // Anchor the chip's center to the fill edge, but clamp so
            // the chip's leading edge never drifts past the bar's leading
            // edge (matters at 0%, where "0%" would otherwise sit slightly
            // inside the bar instead of flush left) and the chip's
            // trailing edge never escapes the bar's trailing edge.
            // `chipWidth` is published by the chip via PreferenceKey, so
            // the clamp uses the actual rendered width.
            let half = chipWidth / 2
            let chipX = max(half, min(width - half, rawX))
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

    private static let tooltipHeight: CGFloat = 18

    /// Track + fill rendered as straight-edged rectangles inside a single
    /// Capsule clip. Mirrors `ProgressBarSpool` so the fill width animates
    /// without ever swapping view identity (avoiding the structural hitch
    /// the previous `EmptyView` ↔ `Capsule` branch produced).
    private func trackWithFill(totalWidth: CGFloat, fillWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Theme.Palette.brandMuted(accent, customHex: customHex)

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
                innerHighlight
                    .frame(width: fillWidth)
            )
            .overlay(
                sheen(width: fillWidth)
                    .frame(width: fillWidth)
                    // Opt the sheen out of the bar's `.animation(.spring,
                    // value: clamped)`. Otherwise, when `clamped` changes
                    // after the band has wrapped to the next cycle, the
                    // spring interpolates the band's offset backwards
                    // through the wrap, producing a visible right → left
                    // ghost motion. Sheen position is driven exclusively
                    // by elapsed time inside `TimelineView`, never by an
                    // animation transaction.
                    .transaction { $0.animation = nil }
            )
            // Confine the sheen band (which uses `.offset` and extends
            // past its layout bounds) to the elapsed fill only, so the
            // light never appears over the muted portion of the bar.
            .clipped()
        }
        .frame(width: totalWidth)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var innerHighlight: some View {
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
    }

    @ViewBuilder
    private func sheen(width: CGFloat) -> some View {
        let bandWidth: CGFloat = max(40, width * 0.35)
        let cycle = Self.sheenCycleSeconds
        let stopAfter = cycle * Self.animatedCycleCount
        // While the popover is hidden, skip the 30fps `TimelineView` entirely.
        // SwiftUI keeps the popover's view tree alive 24/7, so without this
        // gate the sheen would keep ticking the schedule forever even though
        // its body short-circuits to `Color.clear` after 3 cycles.
        if isPopoverVisible {
            // Cap at 30fps. The sheen is a slow horizontal sweep; pumping at
            // 120Hz on ProMotion displays burns CPU without any visible
            // smoothness gain, and the bar is also re-rendered by the outer
            // SwiftUI tree whenever `value` changes.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(sessionStart)
                if elapsed >= stopAfter {
                    Color.clear
                } else {
                    let phase = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
                    // Band's leading edge travels from off-screen-left
                    // (`-bandWidth`) to off-screen-right (`width + bandWidth`).
                    // Anchored to the leading edge of an explicit ZStack so
                    // the band's position is unambiguous (no center-alignment
                    // halving) and motion is always strictly left → right.
                    let leadingX = -bandWidth + CGFloat(phase) * (width + bandWidth * 2)
                    ZStack(alignment: .leading) {
                        Color.clear
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.65), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: bandWidth)
                        .offset(x: leadingX)
                        .blendMode(.plusLighter)
                    }
                }
            }
            .allowsHitTesting(false)
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 14) {
            ProgressBarPremium(value: 0)
            ProgressBarPremium(value: 0.04)
            ProgressBarPremium(value: 0.18)
            ProgressBarPremium(value: 0.62)
            ProgressBarPremium(value: 0.92)
            ProgressBarPremium(value: 1.0)
            ProgressBarPremium(value: 0.62, showsPercent: false)
        }
        .padding()
        .frame(width: 320)
    }
#endif
