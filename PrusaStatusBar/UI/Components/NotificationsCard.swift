import AppKit
import SwiftUI
import UserNotifications

/// Per-state notifications selector. Primary toggle is the kill switch;
/// three sub-rows toggle individual events.
///
/// Visual contract (spec: openspec/specs/notifications):
/// - Sub-rows are hidden when the primary toggle is OFF; their stored values
///   are preserved.
/// - When the primary is ON but OS authorization is denied, an inline amber
///   warning row appears above the sub-rows with a deep-link to System
///   Settings.
struct NotificationsCard: View {
    @Bindable var model: AppModel
    let services: AppServices

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    private struct Row {
        let state: PrinterState
        let titleKey: String
        let descriptionKey: String
    }

    private static let startedRow = Row(
        state: .printing,
        titleKey: "notification.started.title",
        descriptionKey: "notification.started.description"
    )

    private static let finishedRow = Row(
        state: .finished,
        titleKey: "notification.finished.title",
        descriptionKey: "notification.finished.description"
    )

    private static let attentionRow = Row(
        state: .attention,
        titleKey: "notification.attention.title",
        descriptionKey: "notification.attention.description"
    )

    private static let errorRow = Row(
        state: .error,
        titleKey: "notification.error.title",
        descriptionKey: "notification.error.description"
    )

    var body: some View {
        VStack(spacing: 0) {
            primaryRow
            if showAuthWarning {
                authWarningRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if model.notificationsEnabled {
                Divider()
                subRow(Self.startedRow, isOn: notifyOnStartedBinding, isLast: false)
                subRowDivider
                subRow(Self.finishedRow, isOn: notifyOnFinishedBinding, isLast: false)
                subRowDivider
                subRow(Self.attentionRow, isOn: notifyOnAttentionBinding, isLast: false)
                subRowDivider
                subRow(Self.errorRow, isOn: notifyOnErrorBinding, isLast: true)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.notificationsEnabled)
        .animation(.easeInOut(duration: 0.18), value: showAuthWarning)
        .task { await refreshAuthorization() }
    }

    private var showAuthWarning: Bool {
        model.notificationsEnabled && model.notificationsAuthorized == false
    }

    private var authWarningRow: some View {
        HStack(spacing: Theme.Spacing.med) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.stateAmber.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.stateAmber)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("notification.blocked.title"))
                    .font(.prusaCaptionStrong)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(L10n.t("notification.blocked.message"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.sml)
            Button(L10n.t("notification.blocked.action"), action: openSystemSettings)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.stateAmber)
        }
        .padding(.vertical, Theme.Spacing.sml)
        .padding(.horizontal, Theme.Spacing.sml)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Theme.Palette.stateAmber.opacity(0.06))
        )
        .padding(.bottom, Theme.Spacing.sml)
    }

    // MARK: - Primary row

    private var primaryRow: some View {
        HStack(spacing: Theme.Spacing.med) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.brandMuted(accent, customHex: customHex))
                    .frame(width: 28, height: 28)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand(accent, customHex: customHex))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("notification.card.title"))
                    .font(.prusaBody)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(L10n.t("notification.card.subtitle"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 0)
            styledToggle(notificationsEnabledBinding)
        }
        .padding(.bottom, Theme.Spacing.sml)
    }

    private func styledToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
    }

    // MARK: - Sub rows

    private var subRowDivider: some View {
        Divider()
            .padding(.leading, 40)
    }

    private func subRow(_ row: Row, isOn: Binding<Bool>, isLast: Bool) -> some View {
        HStack(spacing: Theme.Spacing.med) {
            stateBadge(for: row.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(row.titleKey))
                    .font(.prusaCaptionStrong)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(L10n.t(row.descriptionKey))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.sml)
            styledToggle(isOn)
        }
        .padding(.top, Theme.Spacing.sml)
        .padding(.bottom, isLast ? 0 : Theme.Spacing.sml)
    }

    private func stateBadge(for state: PrinterState) -> some View {
        ZStack {
            Circle()
                .fill(tint(for: state).opacity(0.16))
                .frame(width: 28, height: 28)
            Image(systemName: glyph(for: state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(for: state))
        }
    }

    private func glyph(for state: PrinterState) -> String {
        switch state {
        case .printing: "play.fill"
        case .finished: "checkmark.seal.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        default: "bell.fill"
        }
    }

    private func tint(for state: PrinterState) -> Color {
        switch state {
        case .printing: Theme.Palette.statePrintingOrange
        case .finished: Theme.Palette.stateGreen
        case .attention: Theme.Palette.stateRed
        case .error: Theme.Palette.stateRed
        default: Theme.Palette.stateNeutral
        }
    }

    // MARK: - Bindings (read AppModel, write through to UserPreferences)

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.notificationsEnabled },
            set: { newValue in
                services.settings.notificationsEnabled = newValue
                model.notificationsEnabled = newValue
                if newValue {
                    Task { await reAuthorizeAndDeepLinkIfNeeded() }
                }
            }
        )
    }

    /// Called every time the user flips the master toggle ON. Re-requests OS
    /// authorization (no-op if already granted or previously denied), refreshes
    /// the cached status, and if the OS still refuses, opens System Settings to
    /// the app's Notifications pane so the user can fix it without hunting.
    @MainActor
    private func reAuthorizeAndDeepLinkIfNeeded() async {
        let notifier = services.notifier
        _ = await notifier.requestAuthorization()
        await refreshAuthorization()
        if model.notificationsAuthorized == false {
            openSystemSettings()
        }
    }

    @MainActor
    private func refreshAuthorization() async {
        let status = await services.notifier.authorizationStatus()
        model.notificationsAuthorized = (status == .authorized || status == .provisional)
    }

    private func openSystemSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var notifyOnStartedBinding: Binding<Bool> {
        Binding(
            get: { model.notifyOnStarted },
            set: { newValue in
                services.settings.notifyOnStarted = newValue
                model.notifyOnStarted = newValue
            }
        )
    }

    private var notifyOnFinishedBinding: Binding<Bool> {
        Binding(
            get: { model.notifyOnFinished },
            set: { newValue in
                services.settings.notifyOnFinished = newValue
                model.notifyOnFinished = newValue
            }
        )
    }

    private var notifyOnAttentionBinding: Binding<Bool> {
        Binding(
            get: { model.notifyOnAttention },
            set: { newValue in
                services.settings.notifyOnAttention = newValue
                model.notifyOnAttention = newValue
            }
        )
    }

    private var notifyOnErrorBinding: Binding<Bool> {
        Binding(
            get: { model.notifyOnError },
            set: { newValue in
                services.settings.notifyOnError = newValue
                model.notifyOnError = newValue
            }
        )
    }
}
