import SwiftUI

/// Optional Buddy Camera configuration shown on the Printer tab. The section
/// is always visible so the feature is discoverable, but the "Enable Buddy
/// Camera" toggle is disabled until the user has set the PrusaLink URL.
/// The toggle gates the host field, derived caption, and inline Test button.
/// Persistence happens through the parent's debounced auto-save (the
/// section has no Save button of its own).
struct BuddyCameraSection: View {
    @Binding var enabled: Bool
    @Binding var cameraHost: String
    @Binding var cameraHostError: String?
    let hostValidation: FieldValidationState
    let probe: RTSPProbing
    /// When false, the "Enable Buddy Camera" toggle is disabled and a tooltip
    /// explains why. The host row stays bound to the existing `enabled` flag,
    /// so users who previously turned the camera on then cleared the URL keep
    /// their host visible (read-only) until they restore the URL.
    let isPrinterURLSet: Bool

    @State private var cameraResult: PrinterTestResult?
    @State private var isTestingCamera: Bool = false

    /// Pure predicate for the toggle's enabled state, exposed for tests.
    /// The toggle is interactive iff the live PrusaLink URL field has any
    /// non-whitespace content. The persisted `printerBaseURL` is intentionally
    /// not consulted: the live `@State` mirror in `PrinterTab` updates on
    /// every keystroke, so the toggle re-enables before auto-save fires.
    nonisolated static func isToggleEnabled(forURLField url: String) -> Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            enableToggleRow
            if enabled {
                hostRow
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.2)),
                        removal: .identity
                    ))
            }
        } header: {
            Label(L10n.t("printer.camera.header"), systemImage: "camera.fill")
        } footer: {
            FormFooterText(L10n.t("printer.camera.footer"))
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private var trimmedHost: String {
        cameraHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTestDisabled: Bool {
        !hostValidation.isValid || isTestingCamera
    }

    private var enableToggleRow: some View {
        Toggle(L10n.t("printer.camera.enable.label"), isOn: $enabled)
            .disabled(!isPrinterURLSet)
            .help(isPrinterURLSet ? "" : L10n.t("printer.camera.enable.requires_url"))
    }

    private var hostRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ConnectionRow {
                ConnectionLabelCell(
                    title: L10n.t("printer.camera.host_label"),
                    systemImage: "video",
                    helpInfo: PrinterHelpInfo(
                        bodyKey: "printer.help.camera.body",
                        learnMoreURL: PrinterHelpLinks.camera
                    )
                )
            } content: {
                HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "",
                            text: $cameraHost,
                            prompt: Text("192.168.1.10 or printer-cam.lan")
                        )
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .font(.prusaBody)
                        .lineLimit(1)
                        .frame(width: connectionFieldWidth)
                        if hostValidation.isValid, !derivedCaption.isEmpty {
                            Text(derivedCaption)
                                .font(.prusaCaption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .textSelection(.enabled)
                        }
                        FieldValidationCaption(
                            state: hostValidation,
                            validLabel: L10n.t("printer.field.validation.valid_host")
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    Button {
                        Task { await testCamera() }
                    } label: {
                        Group {
                            if isTestingCamera {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "wave.3.right")
                            }
                        }
                        .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: connectionTestButtonReservedWidth)
                    .disabled(isTestDisabled)
                    .help(L10n.t("printer.camera.test_help"))
                }
            }
            if let cameraResult {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PrinterTestResultLabel(result: cameraResult)
                }
                .padding(.leading, connectionLabelWidth + Theme.Spacing.med)
                .transition(
                    .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cameraResult)
        .animation(.easeInOut(duration: 0.15), value: isTestingCamera)
    }

    private var derivedCaption: String {
        switch BuddyCameraHostDeriver.rtspURL(forHost: cameraHost) {
        case let .success(url): url.absoluteString
        case .failure: ""
        }
    }

    @MainActor
    private func testCamera() async {
        isTestingCamera = true
        cameraResult = nil
        defer { isTestingCamera = false }

        let trimmed = trimmedHost
        switch BuddyCameraHostDeriver.rtspURL(forHost: cameraHost) {
        case .success:
            cameraHostError = nil
        case .failure(.empty):
            cameraResult = .failure(L10n.t("error.camera.empty"))
            return
        case .failure(.containsSchemeOrPort):
            cameraHostError = L10n.t("error.host.invalid")
            cameraResult = .failure(L10n.t("error.host.invalid"))
            return
        }

        let result = await probe.describe(host: trimmed)
        switch result {
        case let .success(info):
            let label = info.sessionDescription?
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
                ?? L10n.t("printer.camera.reachable")
            cameraResult = .success(label)
        case let .failure(error):
            cameraResult = .failure(rtspProbeMessage(error))
        }
    }
}

@MainActor
private func rtspProbeMessage(_ error: RTSPProbeError) -> String {
    switch error {
    case .timeout: return L10n.t("error.rtsp.timeout")
    case let .connectionFailed(reason): return reason
    case .invalidHost: return L10n.t("error.rtsp.invalid_host")
    case .malformedResponse: return L10n.t("error.rtsp.malformed")
    case let .status(code, reason):
        let reasonText = reason.trimmingCharacters(in: .whitespaces)
        if reasonText.isEmpty {
            return String(format: L10n.t("error.rtsp.status"), code)
        }
        return String(format: L10n.t("error.rtsp.status_with_reason"), code, reasonText)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
