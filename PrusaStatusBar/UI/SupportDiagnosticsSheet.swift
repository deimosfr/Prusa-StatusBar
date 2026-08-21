import AppKit
import SwiftUI

struct SupportDiagnosticsSheet: View {
    @Bindable var model: AppModel
    let services: AppServices
    let onClose: () -> Void

    @State private var state: DiagnosticsState = .idle

    init(model: AppModel, services: AppServices, onClose: @escaping () -> Void) {
        self.model = model
        self.services = services
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.med) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.Palette.statePrintingOrange)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.statePrintingOrangeMuted, in: Circle())

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(L10n.t("about.diagnostics.title"))
                        .font(.prusaTitle)
                    Text(L10n.t("about.diagnostics.description"))
                        .font(.prusaCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(Theme.Spacing.xlg)

            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.med) {
                Label(L10n.t("about.diagnostics.privacy"), systemImage: "lock.shield")
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)

                if let message = diagnosticsStatusMessage {
                    Label(message, systemImage: diagnosticsStatusSymbol)
                        .font(.prusaCaption)
                        .foregroundStyle(diagnosticsStatusColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xlg)

            Divider()

            HStack {
                Spacer()
                Button(L10n.t("about.diagnostics.close"), action: onClose)
                Button(
                    action: { Task { await copyDiagnostics() } },
                    label: {
                        HStack(spacing: Theme.Spacing.sml) {
                            if state == .checking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "doc.on.clipboard")
                            }
                            Text(state == .checking
                                ? L10n.t("about.diagnostics.checking")
                                : L10n.t("about.diagnostics.copy"))
                        }
                    }
                )
                .keyboardShortcut(.defaultAction)
                .disabled(state == .checking)
            }
            .padding(Theme.Spacing.lrg)
        }
        .frame(width: 480)
        .background(Theme.Palette.surfaceElevated)
    }

    @MainActor
    private func copyDiagnostics() async {
        state = .checking
        switch await services.client.fetchDiagnosticSnapshot() {
        case let .success(snapshot):
            let report = snapshot.markdown(
                showNozzleDiameter: model.showNozzleDiameter,
                configuredNozzleDiameters: model.configuredNozzleDiameters,
                effectiveNozzleDiameters: model.effectiveNozzleDiameters
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(report, forType: .string)
            state = .copied
        case let .failure(error):
            state = .failed(diagnosticsMessage(for: error))
        }
    }

    private func diagnosticsMessage(for error: PrinterDiagnosticsError) -> String {
        switch error {
        case let .printer(error):
            error.localizedUserDescription
        case .invalidResponse:
            L10n.t("about.diagnostics.invalid_response")
        }
    }

    private var diagnosticsStatusMessage: String? {
        switch state {
        case .idle, .checking:
            nil
        case .copied:
            L10n.t("about.diagnostics.copied")
        case let .failed(error):
            error
        }
    }

    private var diagnosticsStatusSymbol: String {
        if case .copied = state {
            return "checkmark.circle.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var diagnosticsStatusColor: Color {
        if case .copied = state {
            return Theme.Palette.stateGreen
        }
        return Theme.Palette.stateRed
    }
}

private enum DiagnosticsState: Equatable {
    case idle
    case checking
    case copied
    case failed(String)
}
