import AppKit
import SwiftUI

struct MenuBarTab: View {
    @Bindable var model: AppModel
    let services: AppServices

    @FocusState private var emojiFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle(isOn: showRemainingTimeBinding) {
                    Label(L10n.t("menubar.remaining_time.label"), systemImage: "clock")
                }
                Toggle(isOn: showPercentageBinding) {
                    Label(L10n.t("menubar.percentage.label"), systemImage: "percent")
                }
                HStack(alignment: .center, spacing: Theme.Spacing.med) {
                    Label {
                        Text(L10n.t("menubar.disconnected_icon.style.label"))
                            .font(.prusaBody)
                    } icon: {
                        Image(StatusPresenter.AssetName.disconnected)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                    Spacer(minLength: Theme.Spacing.sml)
                    DisconnectedIconStylePicker(
                        style: disconnectedIconStyleBinding,
                        emoji: model.disconnectedIconEmoji,
                        onPickEmoji: openEmojiPicker
                    )
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .background(emojiCaptureField)
            } header: {
                Text(L10n.t("menubar.label.header"))
            } footer: {
                FormFooterText(L10n.t("menubar.label.footer"))
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Label(L10n.t("menubar.refresh_connected.label"), systemImage: "arrow.clockwise")
                            .font(.prusaBody)
                        InlineHelpButton(body: String(
                            format: L10n.t("menubar.refresh_connected.footer"),
                            UserPreferences.refreshIntervalMin,
                            UserPreferences.refreshIntervalMax / 60
                        ))
                        Spacer(minLength: 0)
                    }
                    RefreshIntervalEditor(
                        seconds: refreshIntervalBinding,
                        bounds: UserPreferences.refreshIntervalMin ... UserPreferences.refreshIntervalMax
                    )
                }
                .padding(.vertical, Theme.Spacing.xxs)
                VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Label(L10n.t("menubar.refresh_disconnected.label"), systemImage: "wifi.exclamationmark")
                            .font(.prusaBody)
                        InlineHelpButton(body: String(
                            format: L10n.t("menubar.refresh_disconnected.footer"),
                            UserPreferences.disconnectedRefreshIntervalMin,
                            UserPreferences.disconnectedRefreshIntervalMax / 60
                        ))
                        Spacer(minLength: 0)
                    }
                    RefreshIntervalEditor(
                        seconds: disconnectedRefreshIntervalBinding,
                        bounds: UserPreferences.disconnectedRefreshIntervalMin
                            ... UserPreferences.disconnectedRefreshIntervalMax
                    )
                }
                .padding(.vertical, Theme.Spacing.xxs)
            } header: {
                Text(L10n.t("menubar.refresh_connected.header"))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .id(model.appLanguage)
    }

    /// Invisible single-character TextField that receives emoji input from
    /// `NSApp.orderFrontCharacterPalette`. The palette inserts the chosen
    /// glyph into the first responder of the key window, so we keep this
    /// 1pt field focused while the palette is open and let its binding
    /// propagate the new emoji into preferences.
    private var emojiCaptureField: some View {
        TextField("", text: disconnectedIconEmojiBinding)
            .textFieldStyle(.plain)
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
            .focused($emojiFieldFocused)
            .accessibilityHidden(true)
    }

    private func openEmojiPicker() {
        emojiFieldFocused = true
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    private var showRemainingTimeBinding: Binding<Bool> {
        Binding(
            get: { model.showRemainingTime },
            set: { newValue in
                services.settings.showRemainingTime = newValue
                model.showRemainingTime = newValue
            }
        )
    }

    private var showPercentageBinding: Binding<Bool> {
        Binding(
            get: { model.showPercentage },
            set: { newValue in
                services.settings.showPercentage = newValue
                model.showPercentage = newValue
            }
        )
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { model.refreshIntervalSeconds },
            set: { newValue in
                services.settings.refreshIntervalSeconds = newValue
                model.refreshIntervalSeconds = services.settings.refreshIntervalSeconds
            }
        )
    }

    private var disconnectedRefreshIntervalBinding: Binding<Int> {
        Binding(
            get: { model.disconnectedRefreshIntervalSeconds },
            set: { newValue in
                services.settings.disconnectedRefreshIntervalSeconds = newValue
                model.disconnectedRefreshIntervalSeconds = services.settings.disconnectedRefreshIntervalSeconds
            }
        )
    }

    private var disconnectedIconStyleBinding: Binding<DisconnectedIconStyle> {
        Binding(
            get: { model.disconnectedIconStyle },
            set: { newValue in
                services.settings.disconnectedIconStyle = newValue
                model.disconnectedIconStyle = newValue
            }
        )
    }

    private var disconnectedIconEmojiBinding: Binding<String> {
        Binding(
            get: { model.disconnectedIconEmoji },
            set: { newValue in
                services.settings.disconnectedIconEmoji = newValue
                model.disconnectedIconEmoji = services.settings.disconnectedIconEmoji
            }
        )
    }
}
