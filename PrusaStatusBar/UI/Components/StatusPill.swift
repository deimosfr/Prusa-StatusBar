import SwiftUI

/// Small capsule that names the printer's current state with an icon. Color
/// tracks state intent so the user can read it at a glance.
struct StatusPill: View {
    let state: PrinterState
    var disconnected: Bool = false
    var unconfigured: Bool = false
    /// When false (popover hidden), the printing-state animated icon is
    /// swapped for a static template asset so its `Timer` (10Hz frame
    /// swap) does not keep firing while the dropdown is offscreen.
    var isPopoverVisible: Bool = true

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    var body: some View {
        HStack(spacing: 5) {
            iconView
                .frame(width: 12, height: 12)
            Text(label)
                .font(.prusaPill)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(background, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(border, lineWidth: Theme.Hairline.width)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var assetName: String {
        StatusPresenter.assetName(
            for: state,
            isDisconnected: disconnected,
            isConfigured: !unconfigured
        )
    }

    /// The pill icon. For the `.printing` state (and only when neither the
    /// disconnected nor unconfigured override is in effect), render the
    /// shared `AnimatedPrintingIconView` so the popover surface shows
    /// continuous motion while a print is in progress. Every other state
    /// uses the bundled template asset, matching the menu-bar settled
    /// rendering for that state.
    @ViewBuilder
    private var iconView: some View {
        if state == .printing, !disconnected, !unconfigured, isPopoverVisible {
            // `AnimatedPrintingIconView` scales its 18x18 design space to
            // whatever frame is proposed, so a single 12x12 frame here
            // produces a glyph the same size as the surrounding bundled
            // template assets. The view is only mounted while the popover
            // is visible so its `Timer` (10Hz frame swap) is invalidated as
            // soon as the user closes the dropdown.
            AnimatedPrintingIconView()
                .frame(width: 12, height: 12)
        } else {
            Image(assetName)
                .renderingMode(.template)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
        }
    }

    private var label: String {
        if unconfigured { return L10n.t("status.unconfigured") }
        if disconnected { return L10n.t("status.disconnected") }
        return switch state {
        case .idle: L10n.t("status.idle")
        case .ready: L10n.t("status.ready")
        case .busy: L10n.t("status.busy")
        case .printing: L10n.t("status.printing")
        case .paused: L10n.t("status.paused")
        case .finished: L10n.t("status.finished")
        case .stopped: L10n.t("status.stopped")
        case .error: L10n.t("status.error")
        case .attention: L10n.t("status.attention")
        }
    }

    private var foreground: Color {
        if unconfigured { return Theme.Palette.stateNeutral }
        if disconnected { return Theme.Palette.stateNeutral }
        return switch state {
        case .printing: Theme.Palette.statePrintingOrange
        case .paused: Theme.Palette.stateYellow
        case .busy: Theme.Palette.brand(accent, customHex: customHex)
        case .finished: Theme.Palette.stateGreen
        case .error: Theme.Palette.stateRed
        case .attention: Theme.Palette.stateRed
        case .stopped: Theme.Palette.statePink
        case .idle, .ready: Theme.Palette.stateNeutral
        }
    }

    private var background: Color {
        if unconfigured || disconnected { return Theme.Palette.stateNeutral.opacity(0.14) }
        return switch state {
        case .printing: Theme.Palette.statePrintingOrangeMuted
        case .paused: Theme.Palette.stateYellow.opacity(0.14)
        case .busy: Theme.Palette.brandMuted(accent, customHex: customHex)
        case .finished: Theme.Palette.stateGreen.opacity(0.14)
        case .error: Theme.Palette.stateRed.opacity(0.14)
        case .attention: Theme.Palette.stateRed.opacity(0.14)
        case .stopped: Theme.Palette.statePink.opacity(0.14)
        case .idle, .ready: Theme.Palette.stateNeutral.opacity(0.12)
        }
    }

    private var border: Color {
        Theme.Palette.hairline
    }
}

#if DEBUG
    #Preview("StatusPill, all states") {
        VStack(alignment: .leading, spacing: 8) {
            StatusPill(state: .printing)
            StatusPill(state: .paused)
            StatusPill(state: .finished)
            StatusPill(state: .error)
            StatusPill(state: .attention)
            StatusPill(state: .idle)
            StatusPill(state: .stopped)
            StatusPill(state: .busy)
            StatusPill(state: .idle, disconnected: true)
            StatusPill(state: .idle, unconfigured: true)
        }
        .padding()
    }
#endif
