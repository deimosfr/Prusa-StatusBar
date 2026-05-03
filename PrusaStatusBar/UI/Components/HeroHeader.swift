import SwiftUI

/// Top of the popover: printer name with the status pill stacked directly
/// below it (leading-aligned), plus a live "updated Xs ago, next in Ys"
/// ticker that re-renders every second via `TimelineView`. The Refresh
/// action lives on the same line as the ticker (right side) per
/// `openspec/specs/menu-bar-ui/spec.md`.
struct HeroHeader: View {
    let printerName: String
    let state: PrinterState
    let isDisconnected: Bool
    let isUnconfigured: Bool
    let lastUpdate: Date?
    let isRefreshing: Bool
    let refreshIntervalSeconds: Int
    var showStatusPill: Bool = true
    /// When false (popover hidden), the periodic ticker is replaced with a
    /// static `Text` so SwiftUI dismantles the `TimelineView` and stops
    /// driving 1Hz wakeups while the dropdown is offscreen.
    var isPopoverVisible: Bool = true
    let onRefresh: () -> Void
    /// Left header slot (`headerLeft`). Pass `.default` and
    /// `leftVisible: false` to disable; the spacer still occupies 32pt so
    /// the title remains centered.
    var leftConfig: CustomActionConfig = .default
    var rightConfig: CustomActionConfig = .default
    var leftVisible: Bool = false
    var rightVisible: Bool = false
    var leftFeedback: CustomActionFeedback = .idle
    var rightFeedback: CustomActionFeedback = .idle
    var onRunLeft: () -> Void = {}
    var onRunRight: () -> Void = {}

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                CustomActionIconButton(
                    config: leftConfig,
                    feedback: leftFeedback,
                    isVisible: leftVisible,
                    action: onRunLeft
                )
                Text(printerName)
                    .font(.prusaTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                CustomActionIconButton(
                    config: rightConfig,
                    feedback: rightFeedback,
                    isVisible: rightVisible,
                    action: onRunRight
                )
            }

            if showStatusPill {
                StatusPill(
                    state: state,
                    disconnected: isDisconnected,
                    unconfigured: isUnconfigured,
                    isPopoverVisible: isPopoverVisible
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 6) {
                ticker
                    .frame(maxWidth: .infinity, alignment: .leading)

                RefreshButton(accent: accent, customHex: customHex, action: onRefresh)
            }
        }
    }

    @ViewBuilder
    private var ticker: some View {
        // SwiftUI keeps the popover's `NSHostingController` view tree alive
        // for the entire app lifetime, so a `TimelineView(.periodic)` inside
        // it would tick every second forever. Swap to a static `Text` while
        // the popover is hidden; SwiftUI dismantles the inactive branch and
        // stops the 1Hz wakeup cost.
        if isPopoverVisible {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(updateLine(now: context.date))
                    .font(.prusaCaption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(updateLine(now: Date()))
                .font(.prusaCaption.monospacedDigit())
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func updateLine(now: Date) -> String {
        guard let lastUpdate else {
            return isUnconfigured
                ? L10n.t("hero.update.not_connected")
                : L10n.t("hero.update.waiting")
        }
        let elapsed = max(0, Int(now.timeIntervalSince(lastUpdate)))
        let lastPart = String(format: L10n.t("hero.update.ago"), elapsed)

        guard !isUnconfigured, !isDisconnected, refreshIntervalSeconds > 0 else {
            return lastPart
        }
        if isRefreshing {
            return String(format: L10n.t("hero.update.refreshing"), lastPart)
        }
        let nextDelta = max(0, refreshIntervalSeconds - elapsed)
        return String(format: L10n.t("hero.update.next_in"), lastPart, nextDelta)
    }
}

private struct RefreshButton: View {
    let accent: Theme.Accent
    let customHex: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 28, height: 24)
            .foregroundStyle(
                isHovering
                    ? Theme.Palette.brand(accent, customHex: customHex)
                    : Theme.Palette.textTertiary
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture { action() }
            .help(L10n.t("a11y.refresh_button"))
            .accessibilityLabel(Text(L10n.t("a11y.refresh_button")))
            .zIndex(1)
            .background(
                Button("", action: action)
                    .keyboardShortcut("r", modifiers: [.command])
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
            )
    }
}
