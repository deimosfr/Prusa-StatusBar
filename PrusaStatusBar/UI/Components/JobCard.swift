import AppKit
import SwiftUI

/// Hero card for the active job: thumbnail, job name, progress bar, and
/// elapsed/remaining timing. Uses a desaturated blurred thumbnail as a
/// subtle backdrop so the card feels like a print-preview poster without
/// leaking saturated colors past the surface tint. The backdrop bitmap is
/// baked once per thumbnail by `JobBackdropRenderer` (cached across frames),
/// so we avoid the edge artifacts that appeared when SwiftUI upscaled a
/// per-frame `.blur` tile under the rounded clip.
struct JobCard: View {
    let job: PrintJob
    let status: PrinterStatus
    let thumbnail: Data?
    let showRemainingTime: Bool
    /// Reset signal forwarded to the underlying progress bar, bumped each
    /// time the menu-bar popover is reopened so animated decorations
    /// restart.
    let progressResetToken: Int
    /// Which progress-bar style to render. `.premium` is the default;
    /// `.spool` swaps the leading-edge dot for the Prusa filament spool.
    let progressBarStyle: ProgressBarStyle
    /// Forwarded to `ProgressBarPremium` so its sheen `TimelineView` is
    /// suspended while the popover is hidden. Defaults to `true` so previews
    /// and isolated callers still animate.
    var isPopoverVisible: Bool = true

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    var body: some View {
        content
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
            )
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let baked = bakedBackdrop {
            Image(nsImage: baked)
                .resizable()
                .scaledToFill()
                .opacity(0.85)
                .overlay(Theme.Palette.surfaceElevated.opacity(0.65))
                .compositingGroup()
        } else {
            Theme.Palette.surfaceElevated
        }
    }

    private var bakedBackdrop: NSImage? {
        guard let data = thumbnail else { return nil }
        return JobBackdropRenderer.render(
            thumbnail: data,
            size: Self.backdropSize,
            scale: Self.backingScale
        )
    }

    private static let backdropSize = CGSize(
        width: Theme.Layout.popoverWidth,
        height: 200
    )

    private static var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.med) {
            HStack(alignment: .center, spacing: Theme.Spacing.med) {
                thumbnailView
                Text(job.displayName)
                    .font(.prusaBody.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let progress = status.progress {
                switch progressBarStyle {
                case .premium:
                    ProgressBarPremium(
                        value: progress,
                        resetToken: progressResetToken,
                        isPopoverVisible: isPopoverVisible
                    )
                case .spool:
                    ProgressBarSpool(value: progress, resetToken: progressResetToken)
                }
            }

            if status.state != .finished {
                timeRow
            }
        }
        .padding(Theme.Layout.cardPadding)
    }

    private var timeRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sml) {
            timeColumn(
                label: L10n.t("dropdown.job.elapsed_label"),
                value: elapsedString,
                symbol: "clock",
                alignment: .leading
            )

            if let etaText {
                Spacer(minLength: 0)
                etaPill(etaText)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }

            timeColumn(
                label: L10n.t("dropdown.job.remaining_label"),
                value: remainingString,
                symbol: "hourglass",
                alignment: .trailing
            )
        }
    }

    private func timeColumn(
        label: String,
        value: String,
        symbol: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                if alignment == .leading {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
                if alignment == .trailing {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Text(value)
                .font(.prusaMetricSmall.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private func etaPill(_ text: String) -> some View {
        VStack(spacing: 2) {
            Text(L10n.t("dropdown.job.eta_label"))
                .font(.system(size: 9, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(text)
                .font(.prusaPill.monospacedDigit())
                .foregroundStyle(Theme.Palette.brand(accent, customHex: customHex))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.brandMuted(accent, customHex: customHex))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Palette.brand(accent, customHex: customHex).opacity(0.25), lineWidth: 0.5)
                )
        }
    }

    private var elapsedString: String {
        guard let elapsed = status.timePrinting, elapsed > 0 else {
            return "--"
        }
        return StatusPresenter.formatCompactDuration(seconds: Int(elapsed.rounded()))
    }

    private var remainingString: String {
        if !showRemainingTime {
            return "--"
        }
        guard let remaining = status.timeRemaining, remaining > 0 else {
            return "--"
        }
        return StatusPresenter.formatCompactDuration(seconds: Int(remaining.rounded()))
    }

    private var etaText: String? {
        guard showRemainingTime,
              let remaining = status.timeRemaining,
              remaining > 0
        else {
            return nil
        }
        let eta = Date().addingTimeInterval(remaining)
        return StatusPresenter.formatEtaPill(eta: eta)
    }

    private var thumbnailView: some View {
        Group {
            if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Theme.Layout.heroThumbnail, height: Theme.Layout.heroThumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
                    )
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                    .fill(Theme.Palette.brandMuted(accent, customHex: customHex))
                    .frame(width: Theme.Layout.heroThumbnail, height: Theme.Layout.heroThumbnail)
                    .overlay(
                        Image(systemName: "cube")
                            .font(.system(size: 24, weight: .ultraLight))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.Palette.brand(accent, customHex: customHex))
                    )
            }
        }
    }

    private var nsImage: NSImage? {
        guard let data = thumbnail else { return nil }
        return NSImage(data: data)
    }
}
