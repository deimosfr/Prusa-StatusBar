import SwiftUI

/// Collapsible row of job-control buttons (Resume / Pause / Stop) shown in
/// the dropdown above the PrusaLink / PrusaConnect links row. Mounted only
/// while a job is active. Each button's per-state validity is computed by
/// `ActionsSection.isEnabled(_:for:)` so the rule is unit-testable without
/// standing up SwiftUI.
struct ActionsSection: View {
    enum Action: Equatable {
        case resume
        case pause
        case stop
    }

    let state: PrinterState
    let onResume: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    @State private var expanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    private let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            header
            if expanded {
                buttonsRow
            }
        }
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.sml) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(L10n.t("dropdown.actions.header"))
                    .font(.prusaCaptionStrong)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: expanded)
            }
            .padding(.horizontal, Theme.Spacing.med)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Theme.Palette.surfaceElevated,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
        )
        .accessibilityLabel(
            expanded
                ? L10n.t("dropdown.actions.state_expanded")
                : L10n.t("dropdown.actions.state_collapsed")
        )
        .accessibilityAddTraits(.isButton)
    }

    private var buttonsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.allActions.enumerated()), id: \.offset) { idx, action in
                if idx > 0 {
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(width: Theme.Hairline.width)
                }
                ActionButton(
                    action: action,
                    isEnabled: Self.isEnabled(action, for: state),
                    accent: accent,
                    customHex: customHex,
                    onTap: { trigger(action) }
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

    private static let allActions: [Action] = [.resume, .pause, .stop]

    private func trigger(_ action: Action) {
        switch action {
        case .resume: onResume()
        case .pause: onPause()
        case .stop: onStop()
        }
    }

    /// Per-state validity matrix from the spec. Exposed (internal,
    /// `static`, `nonisolated`) so `ActionsSectionTests` can assert it
    /// without instantiating the view.
    nonisolated static func isEnabled(_ action: Action, for state: PrinterState) -> Bool {
        switch action {
        case .resume:
            state == .paused
        case .pause:
            state == .printing
        case .stop:
            state == .printing || state == .paused || state == .attention
        }
    }
}

private struct ActionButton: View {
    let action: ActionsSection.Action
    let isEnabled: Bool
    let accent: Theme.Accent
    let customHex: String
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(.prusaCaptionStrong)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isEnabled && isHovering ? Theme.Palette.brandMuted(accent, customHex: customHex) : Color.clear)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1.0 : 0.45)
        .disabled(!isEnabled)
        .help(tooltip)
        .onHover { isHovering = $0 }
    }

    private var symbol: String {
        switch action {
        case .resume: "play.fill"
        case .pause: "pause.fill"
        case .stop: "stop.fill"
        }
    }

    private var label: String {
        switch action {
        case .resume: L10n.t("actions.resume")
        case .pause: L10n.t("actions.pause")
        case .stop: L10n.t("actions.stop")
        }
    }

    private var tooltip: String {
        if isEnabled {
            switch action {
            case .resume: return L10n.t("actions.resume.tooltip")
            case .pause: return L10n.t("actions.pause.tooltip")
            case .stop: return L10n.t("actions.stop.tooltip")
            }
        }
        switch action {
        case .resume: return L10n.t("actions.resume.disabled")
        case .pause: return L10n.t("actions.pause.disabled")
        case .stop: return L10n.t("actions.stop.disabled")
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return Theme.Palette.textSecondary
        }
        if action == .stop {
            return isHovering ? Theme.Palette.stateRed : Theme.Palette.textPrimary
        }
        return isHovering ? Theme.Palette.brand(accent, customHex: customHex) : Theme.Palette.textPrimary
    }
}
