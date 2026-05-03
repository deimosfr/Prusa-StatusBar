import SwiftUI

struct MenuContentTab: View {
    @Bindable var model: AppModel
    let services: AppServices

    @State private var prusaConnectUUID: String = ""
    @State private var prusaConnectUUIDError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var isReloading: Bool = false

    var body: some View {
        Form {
            Section {
                ProgressBarStylePickerRow(
                    selection: progressBarStyleBinding,
                    accent: model.accent,
                    customAccentHex: model.customAccentHex
                )
            } header: {
                Text(L10n.t("content.style.header"))
            } footer: {
                FormFooterText(L10n.t("content.style.footer"))
            }

            Section {
                Toggle(isOn: showTemperaturesBinding) {
                    Label(L10n.t("content.metrics.temperature.label"), systemImage: "thermometer.medium")
                }
                Toggle(isOn: showNozzleDiameterBinding) {
                    Label(L10n.t("content.metrics.nozzle_diameter.label"), systemImage: "circle.dotted")
                }
                Toggle(isOn: showFilamentTypeBinding) {
                    Label(L10n.t("content.metrics.filament_type.label"), systemImage: "drop.fill")
                }
                Toggle(isOn: showSpeedBinding) {
                    Label(L10n.t("content.metrics.speed.label"), systemImage: "gauge.medium")
                }
                Toggle(isOn: showZHeightBinding) {
                    Label(L10n.t("content.metrics.z_height.label"), systemImage: "arrow.up.and.down")
                }
                Toggle(isOn: showMMUBinding) {
                    Label(L10n.t("content.metrics.mmu.label"), systemImage: "square.stack.3d.up")
                }
            } header: {
                Text(L10n.t("content.metrics.header"))
            } footer: {
                FormFooterText(L10n.t("content.metrics.footer"))
            }

            Section {
                Toggle(isOn: showJobActionsBinding) {
                    Label(L10n.t("content.job_control.label"), systemImage: "playpause.fill")
                }
            } header: {
                Text(L10n.t("content.job_control.header"))
            } footer: {
                FormFooterText(L10n.t("content.job_control.footer"))
            }

            Section {
                Toggle(isOn: showPrusaLinkButtonBinding) {
                    Label(L10n.t("content.web_links.show_prusalink.label"), systemImage: "safari")
                }
                Toggle(isOn: showPrusaConnectButtonBinding) {
                    Label(L10n.t("content.web_links.show_prusaconnect.label"), systemImage: "cloud")
                }
                if model.showPrusaConnectButton {
                    PrusaConnectUUIDRow(prusaConnectUUID: $prusaConnectUUID, uuidError: prusaConnectUUIDError)
                }
            } header: {
                Text(L10n.t("content.web_links.header"))
            } footer: {
                FormFooterText(L10n.t("content.web_links.footer"))
            }

            Section {
                CustomActionsSection(model: model, services: services)
            } header: {
                Text(L10n.t("content.custom_actions.header"))
            } footer: {
                FormFooterText(L10n.t("content.custom_actions.footer"))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .id(model.appLanguage)
        .onAppear { reloadFromStorage() }
        .onDisappear {
            saveTask?.cancel()
            if hasUUIDChange { savePrusaConnectUUID() }
        }
        .onChange(of: prusaConnectUUID) { _, _ in scheduleAutoSave() }
    }

    private var hasUUIDChange: Bool {
        let trimmed = prusaConnectUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != (services.settings.prusaConnectUUID ?? "")
    }

    private func reloadFromStorage() {
        isReloading = true
        defer { isReloading = false }
        prusaConnectUUID = services.settings.prusaConnectUUID ?? ""
        prusaConnectUUIDError = nil
    }

    private func scheduleAutoSave() {
        if isReloading { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                if hasUUIDChange { savePrusaConnectUUID() }
            }
        }
    }

    private func savePrusaConnectUUID() {
        let trimmed = prusaConnectUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, UUID(uuidString: trimmed) == nil {
            prusaConnectUUIDError = L10n.t("error.uuid.invalid")
            return
        }
        prusaConnectUUIDError = nil
        let stored: String? = trimmed.isEmpty ? nil : trimmed
        services.settings.prusaConnectUUID = stored
        model.prusaConnectUUID = stored ?? ""
        services.onConfigurationChanged()
    }

    private var showPrusaLinkButtonBinding: Binding<Bool> {
        Binding(
            get: { model.showPrusaLinkButton },
            set: { newValue in
                services.settings.showPrusaLinkButton = newValue
                model.showPrusaLinkButton = newValue
            }
        )
    }

    private var showPrusaConnectButtonBinding: Binding<Bool> {
        Binding(
            get: { model.showPrusaConnectButton },
            set: { newValue in
                services.settings.showPrusaConnectButton = newValue
                model.showPrusaConnectButton = newValue
            }
        )
    }

    private var showSpeedBinding: Binding<Bool> {
        Binding(
            get: { model.showSpeed },
            set: { newValue in
                services.settings.showSpeed = newValue
                model.showSpeed = newValue
            }
        )
    }

    private var showZHeightBinding: Binding<Bool> {
        Binding(
            get: { model.showZHeight },
            set: { newValue in
                services.settings.showZHeight = newValue
                model.showZHeight = newValue
            }
        )
    }

    private var showNozzleDiameterBinding: Binding<Bool> {
        Binding(
            get: { model.showNozzleDiameter },
            set: { newValue in
                services.settings.showNozzleDiameter = newValue
                model.showNozzleDiameter = newValue
            }
        )
    }

    private var showFilamentTypeBinding: Binding<Bool> {
        Binding(
            get: { model.showFilamentType },
            set: { newValue in
                services.settings.showFilamentType = newValue
                model.showFilamentType = newValue
            }
        )
    }

    private var showMMUBinding: Binding<Bool> {
        Binding(
            get: { model.showMMU },
            set: { newValue in
                services.settings.showMMU = newValue
                model.showMMU = newValue
            }
        )
    }

    private var showTemperaturesBinding: Binding<Bool> {
        Binding(
            get: { model.showTemperatures },
            set: { newValue in
                services.settings.showTemperatures = newValue
                model.showTemperatures = newValue
            }
        )
    }

    private var showJobActionsBinding: Binding<Bool> {
        Binding(
            get: { model.showJobActions },
            set: { newValue in
                services.settings.showJobActions = newValue
                model.showJobActions = newValue
            }
        )
    }

    private var progressBarStyleBinding: Binding<ProgressBarStyle> {
        Binding(
            get: { model.progressBarStyle },
            set: { newValue in
                services.settings.progressBarStyle = newValue
                model.progressBarStyle = newValue
            }
        )
    }
}

/// Two side-by-side preview cards, one per `ProgressBarStyle`. Each card
/// drives its own animated preview and acts as a button that selects its
/// style; the active card carries an accent ring borrowed from the
/// brand-accent picker treatment.
private struct ProgressBarStylePickerRow: View {
    @Binding var selection: ProgressBarStyle
    let accent: Theme.Accent
    let customAccentHex: String

    var body: some View {
        HStack(spacing: Theme.Spacing.med) {
            card(for: .spool, label: L10n.t("content.style.spool"))
            card(for: .premium, label: L10n.t("content.style.classic"))
        }
        .environment(\.brandAccent, accent)
        .environment(\.brandCustomHex, customAccentHex)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("a11y.style_selector"))
    }

    private func card(for style: ProgressBarStyle, label: String) -> some View {
        let isSelected = selection == style
        return Button {
            if selection != style {
                selection = style
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
                Text(label)
                    .font(.prusaCaptionStrong)
                    .foregroundStyle(Theme.Palette.textPrimary)
                ProgressBarStylePreview(style: style)
                    .frame(height: 36)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.med)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
            )
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card + 2, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Palette.brand(accent, customHex: customAccentHex) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
