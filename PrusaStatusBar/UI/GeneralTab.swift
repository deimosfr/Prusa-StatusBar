import SwiftUI

struct GeneralTab: View {
    @Bindable var model: AppModel
    let services: AppServices

    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: launchAtLoginBinding) {
                    Label(L10n.t("general.launch_at_login.label"), systemImage: "power")
                }
                if let loginError {
                    Text(loginError)
                        .font(.prusaCaption)
                        .foregroundStyle(Theme.Palette.stateRed)
                }
                HStack(alignment: .center, spacing: Theme.Spacing.med) {
                    Label(L10n.t("general.appearance.accent.label"), systemImage: "paintpalette")
                    Spacer(minLength: 0)
                    AccentSwatchPicker(
                        selection: accentBinding,
                        customHex: customAccentHexBinding
                    )
                }
                HStack(alignment: .center, spacing: Theme.Spacing.med) {
                    Label(L10n.t("general.language.label"), systemImage: "globe")
                    Spacer(minLength: 0)
                    Picker("", selection: languageBinding) {
                        ForEach(LanguageCode.allCases) { code in
                            Text(code.displayName).tag(code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Toggle(isOn: checkForUpdatesBinding) {
                    Label(L10n.t("general.check_for_updates.label"), systemImage: "arrow.down.circle")
                }
            } header: {
                Text(L10n.t("general.global.section"))
            } footer: {
                FormFooterText(L10n.t("general.check_for_updates.footer"))
            }

            Section {
                NotificationsCard(model: model, services: services)
            } header: {
                Text(L10n.t("general.notifications.section"))
            } footer: {
                FormFooterText(L10n.t("general.notifications.footer"))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .id(model.appLanguage)
        .onAppear { refreshLoginItemStatus() }
    }

    private var accentBinding: Binding<Theme.Accent> {
        Binding(
            get: { model.accent },
            set: { newValue in
                services.settings.accent = newValue
                model.accent = newValue
            }
        )
    }

    private var customAccentHexBinding: Binding<String> {
        Binding(
            get: { model.customAccentHex },
            set: { newValue in
                services.settings.customAccentHex = newValue
                model.customAccentHex = newValue
            }
        )
    }

    private var languageBinding: Binding<LanguageCode> {
        Binding(
            get: { model.appLanguage },
            set: { newValue in
                services.settings.appLanguage = newValue
                model.appLanguage = newValue
                NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
            }
        )
    }

    private var checkForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { model.checkForUpdatesEnabled },
            set: { newValue in
                let wasEnabled = services.settings.checkForUpdatesEnabled
                services.settings.checkForUpdatesEnabled = newValue
                model.checkForUpdatesEnabled = newValue
                if !newValue {
                    services.settings.latestUpdateTag = nil
                    services.settings.latestUpdateURL = nil
                    model.availableUpdate = nil
                } else if !wasEnabled {
                    services.onRequestUpdateCheck()
                }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { newValue in
                do {
                    try services.loginItem.setEnabled(newValue)
                    loginError = nil
                    model.launchAtLogin = newValue
                } catch {
                    let verb = newValue
                        ? L10n.t("general.launch_at_login.verb_enable")
                        : L10n.t("general.launch_at_login.verb_disable")
                    loginError = String(
                        format: L10n.t("general.launch_at_login.error"),
                        verb,
                        error.localizedDescription
                    )
                    model.launchAtLogin = services.loginItem.currentStatus() == .enabled
                }
            }
        )
    }

    private func refreshLoginItemStatus() {
        model.launchAtLogin = services.loginItem.currentStatus() == .enabled
    }
}
