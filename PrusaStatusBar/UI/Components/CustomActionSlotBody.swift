import AppKit
import SwiftUI

/// Expanded body of a `CustomActionSlotCard`. Hosts the four grouped
/// editing sections (Appearance, Visibility, Request, Behaviour) plus
/// the headers editor and inline Test result pill.
struct CustomActionSlotBody: View {
    @Binding var config: CustomActionConfig
    @Binding var showSymbolPicker: Bool
    @Binding var testResult: CustomActionTestPill?
    @Binding var testTask: Task<Void, Never>?
    @Binding var revealedHeaderValues: Set<UUID>
    let runner: CustomActionRunning

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.med) {
            sectionHeader(L10n.t("prefs.actions.section.appearance"))
            appearanceRow
            sectionHeader(L10n.t("prefs.actions.section.visibility"))
            visibilityPicker
            sectionHeader(L10n.t("prefs.actions.section.request"))
            methodRow
            urlRow
            urlWarningRow
            CustomActionHeadersEditor(
                headers: $config.headers,
                revealedHeaderValues: $revealedHeaderValues
            )
            bodyRow
            sectionHeader(L10n.t("prefs.actions.section.behavior"))
            Toggle(L10n.t("prefs.actions.field.confirm"), isOn: $config.confirmBeforeRun)
                .toggleStyle(.switch)
            testRow
        }
        .padding(.horizontal, Theme.Spacing.med)
        .padding(.vertical, Theme.Spacing.med)
    }

    private var appearanceRow: some View {
        HStack(spacing: 8) {
            Text(L10n.t("prefs.actions.field.name"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Self.requestLabelWidth, alignment: .leading)
            PlainBorderedTextField(
                placeholder: "",
                text: $config.name,
                monospaced: false
            )
            .frame(height: 26)
            Button { showSymbolPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: config.symbol.isEmpty ? "bolt" : config.symbol)
                        .symbolRenderingMode(.hierarchical)
                    Text(L10n.t("prefs.actions.field.symbol"))
                }
                .frame(minWidth: 100)
            }
        }
    }

    private var visibilityPicker: some View {
        Picker("", selection: $config.visibility) {
            Label(
                L10n.t("prefs.actions.visibility.always"),
                systemImage: "infinity"
            )
            .tag(CustomActionVisibility.always)
            Label(
                L10n.t("prefs.actions.visibility.when_connected"),
                systemImage: "wifi"
            )
            .tag(CustomActionVisibility.whenConnected)
            Label(
                L10n.t("prefs.actions.visibility.when_disconnected"),
                systemImage: "wifi.slash"
            )
            .tag(CustomActionVisibility.whenDisconnected)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private static let requestLabelWidth: CGFloat = 56

    private var methodRow: some View {
        HStack(spacing: 8) {
            Text(L10n.t("prefs.actions.field.method_label"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Self.requestLabelWidth, alignment: .leading)
            Picker("", selection: $config.method) {
                ForEach(CustomActionMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            Spacer(minLength: 0)
        }
    }

    private var urlRow: some View {
        HStack(spacing: 8) {
            Text(L10n.t("prefs.actions.field.url_label"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Self.requestLabelWidth, alignment: .leading)
            PlainBorderedTextField(
                placeholder: L10n.t("prefs.actions.field.url_placeholder"),
                text: $config.url
            )
            .frame(height: 26)
        }
    }

    @ViewBuilder
    private var urlWarningRow: some View {
        let trimmed = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, URL(string: trimmed) == nil {
            Label(L10n.t("prefs.actions.url_warning"), systemImage: "exclamationmark.triangle.fill")
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.stateAmber)
        }
    }

    private var bodyRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(L10n.t("prefs.actions.field.body_label"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Self.requestLabelWidth, alignment: .leading)
                .padding(.top, 6)
            bodyEditor
        }
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
                )

            if config.body.isEmpty {
                Text(L10n.t("prefs.actions.field.body_placeholder"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.horizontal, 11)
                    .padding(.top, 11)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $config.body)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .multilineTextAlignment(.leading)
                .padding(6)
        }
        .frame(minHeight: 70, maxHeight: 120)
    }

    private var testRow: some View {
        HStack(spacing: Theme.Spacing.sml) {
            Button(L10n.t("prefs.actions.test")) { runTest() }
                .disabled(!canTest)
            if let testResult {
                pill(testResult).transition(.opacity)
            }
        }
    }

    /// The Test button only needs a non-empty URL: the user should be
    /// able to verify a draft before flipping the slot's enable toggle.
    private var canTest: Bool {
        guard testTask == nil else { return false }
        let trimmed = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .prusaSectionHeader()
            .padding(.top, 2)
    }

    private func pill(_ pill: CustomActionTestPill) -> some View {
        Text(pill.text)
            .font(.prusaPill)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(pill.tone.background, in: Capsule())
            .foregroundStyle(pill.tone.foreground)
    }

    private func runTest() {
        testTask?.cancel()
        testResult = nil
        let snapshot = config
        let runnerRef = runner
        testTask = Task { @MainActor in
            let outcome = await runnerRef.run(snapshot)
            switch outcome {
            case let .success(value) where value.isSuccess:
                testResult = CustomActionTestPill(text: pillText(value), tone: .success)
            case let .success(value):
                testResult = CustomActionTestPill(text: pillText(value), tone: .warning)
            case let .failure(error):
                testResult = CustomActionTestPill(text: error.displayDescription, tone: .failure)
            }
            testTask = nil
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled {
                testResult = nil
            }
        }
    }

    private func pillText(_ outcome: CustomActionRunOutcome) -> String {
        let ms = Int(outcome.duration * 1000)
        return "\(outcome.httpStatus) -- \(ms) ms"
    }
}
