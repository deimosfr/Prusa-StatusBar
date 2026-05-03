import AppKit
import SwiftUI

/// Single slot card rendered inside `CustomActionsTab`. Header row with
/// enable toggle + status dot + symbol preview + chevron; expanded body
/// hosts grouped editing sections + Test button. Split out of
/// `CustomActionsTab.swift` to stay under the file/struct lint budgets.
struct CustomActionSlotCard: View {
    let slot: CustomActionSlot
    @Binding var config: CustomActionConfig
    let runner: CustomActionRunning
    @Binding var recents: [String]
    let accent: Theme.Accent
    let customAccentHex: String

    @State private var expanded: Bool = false
    @State private var showSymbolPicker: Bool = false
    @State private var testResult: CustomActionTestPill?
    @State private var testTask: Task<Void, Never>?
    @State private var revealedHeaderValues: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                Divider()
                CustomActionSlotBody(
                    config: $config,
                    showSymbolPicker: $showSymbolPicker,
                    testResult: $testResult,
                    testTask: $testTask,
                    revealedHeaderValues: $revealedHeaderValues,
                    runner: runner
                )
            }
        }
        .onChange(of: config.url) { _, _ in syncEnabledIfBlocked() }
        .onChange(of: config.symbol) { _, _ in syncEnabledIfBlocked() }
        .onChange(of: config.name) { _, _ in syncEnabledIfBlocked() }
        .background(
            Theme.Palette.surfaceElevated,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
        )
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerSheet(
                selection: Binding(
                    get: { config.symbol },
                    set: { config.symbol = $0 }
                ),
                recents: $recents,
                onClose: { showSymbolPicker = false }
            )
            .environment(\.brandAccent, accent)
            .environment(\.brandCustomHex, customAccentHex)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sml) {
            Toggle("", isOn: $config.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!canEnable)
                .opacity(canEnable ? 1.0 : 0.55)
                .overlay {
                    if !canEnable {
                        Color.clear
                            .contentShape(Rectangle())
                            .help(enableBlockedReason)
                    }
                }
            Image(systemName: config.symbol.isEmpty ? "bolt" : config.symbol)
                .font(.system(size: 14, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.Palette.brand(accent, customHex: customAccentHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(slotLabel)
                    .font(.prusaCaptionStrong)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(headerSubtitle)
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.med)
        .padding(.vertical, Theme.Spacing.sml)
    }

    private var hasURL: Bool {
        !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSymbol: Bool {
        !config.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasName: Bool {
        !config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canEnable: Bool {
        guard hasURL else { return false }
        return slot.isHeader ? (hasSymbol && hasName) : (hasSymbol || hasName)
    }

    private var enableBlockedReason: String {
        var items: [String] = []
        if !hasURL { items.append(L10n.t("prefs.actions.toggle.requirement.url")) }
        if slot.isHeader {
            if !hasSymbol { items.append(L10n.t("prefs.actions.toggle.requirement.icon")) }
            if !hasName { items.append(L10n.t("prefs.actions.toggle.requirement.name")) }
        } else if !hasSymbol, !hasName {
            items.append(L10n.t("prefs.actions.toggle.requirement.name_or_icon"))
        }
        guard !items.isEmpty else { return "" }
        let header = L10n.t("prefs.actions.toggle.requirements_header")
        let bullets = items.map { "• \($0)" }.joined(separator: "\n")
        return "\(header)\n\(bullets)"
    }

    private func syncEnabledIfBlocked() {
        if config.enabled, !canEnable {
            config.enabled = false
        }
    }

    private var slotLabel: String {
        switch slot {
        case .headerLeft: L10n.t("prefs.actions.slot.header_left")
        case .headerRight: L10n.t("prefs.actions.slot.header_right")
        case .rowLeft: L10n.t("prefs.actions.slot.row_left")
        case .rowRight: L10n.t("prefs.actions.slot.row_right")
        case .rowSecondLeft: L10n.t("prefs.actions.slot.row_second_left")
        case .rowSecondRight: L10n.t("prefs.actions.slot.row_second_right")
        }
    }

    private var headerSubtitle: String {
        let name = config.name.isEmpty ? L10n.t("custom_action.untitled") : config.name
        let visibility: String = switch config.visibility {
        case .always: L10n.t("prefs.actions.preview.visibility.always")
        case .whenConnected: L10n.t("prefs.actions.preview.visibility.when_connected")
        case .whenDisconnected: L10n.t("prefs.actions.preview.visibility.when_disconnected")
        }
        let confirmation = config.confirmBeforeRun
            ? L10n.t("prefs.actions.preview.confirm_on")
            : L10n.t("prefs.actions.preview.confirm_off")
        return "\(name) · \(visibility) · \(confirmation)"
    }
}
