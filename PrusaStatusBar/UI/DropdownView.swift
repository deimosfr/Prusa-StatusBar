import AppKit
import SwiftUI

/// Body of the popover shown when the user left-clicks the menu-bar icon.
/// All state comes from `AppModel`; actions are delegated to closures owned
/// by `MenuBarController`.
///
/// Information contract preserved per `openspec/specs/menu-bar-ui/spec.md`:
/// printer name + state, job + thumbnail, progress + elapsed/remaining,
/// nozzle temp, bed temp, last-update, refresh, preferences, quit.
struct DropdownView: View {
    @Bindable var model: AppModel

    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onConfigurePrinter: () -> Void
    let onQuit: () -> Void
    let onOpenPrusaLink: () -> Void
    let onOpenPrusaConnect: () -> Void
    let onResume: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    var onOpenRelease: () -> Void = {}
    /// Async runner for the four custom action slots. The returned outcome
    /// drives the per-slot feedback state (success tick / failure cross).
    var onRunCustomAction: (CustomActionSlot) async -> Result<CustomActionRunOutcome, CustomActionError> = { _ in
        .failure(.slotMissingConfig)
    }

    /// Opens a Quick Look popup window for the given camera kind and
    /// source. Wired by `MenuBarController` to a per-kind
    /// `CameraQuickLookWindowController`. No-op default keeps SwiftUI
    /// previews and tests free from window-controller plumbing.
    var onZoomCamera: (CameraTileKind, CameraQuickLookSource) -> Void = { _, _ in }

    /// Detaches the dropdown into a persistent floating window. `nil`
    /// hides the button (used inside the detached window to prevent
    /// circular detach).
    var onDetach: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var customActionFeedback: [CustomActionSlot: CustomActionFeedback] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.med) {
            HeroHeader(
                printerName: model.resolvedPrinterName,
                state: model.lastStatus?.state ?? .idle,
                isDisconnected: model.isDisconnected,
                isUnconfigured: !model.isConfigured,
                lastUpdate: model.lastUpdate,
                isRefreshing: model.isRefreshing,
                refreshIntervalSeconds: model.refreshIntervalSeconds,
                showStatusPill: model.isConfigured,
                isPopoverVisible: model.popoverVisible,
                onRefresh: onRefresh,
                leftConfig: customConfig(.headerLeft),
                rightConfig: customConfig(.headerRight),
                leftVisible: isCustomVisible(.headerLeft),
                rightVisible: isCustomVisible(.headerRight),
                leftFeedback: customActionFeedback[.headerLeft] ?? .idle,
                rightFeedback: customActionFeedback[.headerRight] ?? .idle,
                onRunLeft: { runCustomAction(.headerLeft) },
                onRunRight: { runCustomAction(.headerRight) }
            )

            // Detached window: render middleStack with its natural intrinsic
            // size so NSHostingController's preferredContentSize reflects the
            // real content height. The controller uses that to auto-fit the
            // window. If the user manually shrinks the window, content clips
            // (acceptable trade-off vs. an always-empty scroll area).
            // Popover: ViewThatFits prefers no scroll; falls back to ScrollView
            // with permanent indicator when content overflows the fixed popover
            // height.
            if model.detachedWindowVisible {
                middleStack
            } else {
                ViewThatFits(in: .vertical) {
                    middleStack
                    ScrollView(.vertical, showsIndicators: true) {
                        middleStack
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            FooterBar(onPreferences: onPreferences, onQuit: onQuit,
                      availableUpdate: model.availableUpdate, onOpenRelease: onOpenRelease,
                      onDetach: onDetach)
                .padding(.top, -Theme.Spacing.xxs - 2)
        }
        .padding(.horizontal, Theme.Layout.popoverPadding)
        .padding(.top, Theme.Layout.popoverPadding)
        .padding(.bottom, Theme.Layout.popoverFooterBottomPadding)
        .frame(width: Theme.Layout.popoverWidth, alignment: .topLeading)
        .frame(
            maxHeight: model.detachedWindowVisible ? nil : maxPopoverHeight,
            alignment: .topLeading
        )
        .background(.regularMaterial)
        .environment(\.brandAccent, model.accent)
        .environment(\.brandCustomHex, model.customAccentHex)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.25),
            value: presentationKind
        )
        .onChange(of: model.isDisconnected) { _, nowDisconnected in
            // Drop the per-printer camera tile size cache the moment the
            // printer goes offline, so the next online session can
            // re-measure (different camera resolution after reconnect
            // shouldn't be pinned to the previous height).
            if nowDisconnected {
                model.clearCameraTileHeights()
            }
        }
    }

    private var middleStack: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.med) {
            body(for: presentation)
                .transition(.opacity)

            if let actionState = actionsSectionState(for: presentation) {
                ActionsSection(
                    state: actionState,
                    onResume: onResume,
                    onPause: onPause,
                    onStop: onStop
                )
            }

            if showsLinksRow(for: presentation) {
                LinksRow(
                    prusaLinkVisible: model.showPrusaLinkButton,
                    prusaConnectVisible: model.showPrusaConnectButton,
                    prusaLinkEnabled: Self.shouldEnablePrusaLink(
                        printerBaseURL: model.printerBaseURL,
                        isDisconnected: model.isDisconnected
                    ),
                    prusaLinkDisconnected: model.isDisconnected,
                    prusaConnectEnabled: model.showPrusaConnectButton,
                    onOpenPrusaLink: onOpenPrusaLink,
                    onOpenPrusaConnect: onOpenPrusaConnect
                )
            }

            if isContentOrDisconnected(presentation), hasVisibleCustomActionsRow {
                CustomActionsRow(
                    leftConfig: customConfig(.rowLeft),
                    rightConfig: customConfig(.rowRight),
                    leftVisible: isCustomVisible(.rowLeft),
                    rightVisible: isCustomVisible(.rowRight),
                    leftFeedback: customActionFeedback[.rowLeft] ?? .idle,
                    rightFeedback: customActionFeedback[.rowRight] ?? .idle,
                    onRunLeft: { runCustomAction(.rowLeft) },
                    onRunRight: { runCustomAction(.rowRight) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Variant routing

    private enum Presentation: Equatable {
        case unconfigured
        case disconnected
        case loading
        case content(PrinterStatus)
    }

    private enum PresentationKind: Equatable {
        case unconfigured, disconnected, loading, content
    }

    private var presentation: Presentation {
        if !model.isConfigured { return .unconfigured }
        if model.isDisconnected { return .disconnected }
        if let status = model.lastStatus { return .content(status) }
        return .loading
    }

    @ViewBuilder
    private func body(for presentation: Presentation) -> some View {
        switch presentation {
        case .unconfigured:
            unconfiguredCard
        case .disconnected:
            disconnectedCard
        case .loading:
            loadingCard
        case let .content(status):
            contentBody(for: status)
        }
    }

    // MARK: - States (state body rendering carved out into the

    // same-file extension below to keep `type_body_length` happy.)

    private func temperaturesGrid(status: PrinterStatus) -> some View {
        HStack(spacing: Theme.Spacing.sml) {
            if let nozzle = status.nozzleTemperature {
                TempCard(heater: .nozzle, temperature: nozzle)
            }
            if let bed = status.bedTemperature {
                TempCard(heater: .bed, temperature: bed)
            }
        }
    }

    private func extraRows(for status: PrinterStatus) -> [LiveMetricsCard.Row] {
        var rows: [LiveMetricsCard.Row] = []
        if model.showNozzleDiameter, let diameter = model.printerInfo?.nozzleDiameter {
            rows.append(.init(
                symbol: "circle.dotted",
                label: L10n.t("dropdown.metrics.nozzle_diameter"),
                value: String(format: "%.2f mm", diameter)
            ))
        }
        if model.showFilamentType, let material = status.activeFilamentMaterial {
            rows.append(.init(
                symbol: "drop.fill",
                label: L10n.t("dropdown.metrics.filament_type"),
                value: material
            ))
        }
        if model.showSpeed, let speed = status.speed {
            rows.append(.init(
                symbol: "gauge.medium",
                label: L10n.t("dropdown.metrics.speed"),
                value: "\(Int(speed.rounded()))%"
            ))
        }
        if model.showZHeight, let zHeight = status.zHeight {
            rows.append(.init(
                symbol: "arrow.up.and.down",
                label: L10n.t("dropdown.metrics.z_height"),
                value: String(format: "%.2f mm", zHeight)
            ))
        }
        if model.showMMU, let mmuEnabled = model.printerInfo?.mmuEnabled {
            let valueKey = mmuEnabled
                ? "dropdown.metrics.mmu.enabled"
                : "dropdown.metrics.mmu.disabled"
            rows.append(.init(
                symbol: "square.stack.3d.up",
                label: L10n.t("dropdown.metrics.mmu"),
                value: L10n.t(valueKey)
            ))
        }
        return rows
    }

    /// Returns the `PrinterState` used to drive the Actions section, or
    /// `nil` when the section should not render (idle/finished/disconnected,
    /// no cached job, or master toggle off).
    private func actionsSectionState(for presentation: Presentation) -> PrinterState? {
        guard case let .content(status) = presentation else { return nil }
        guard model.lastJob != nil, Self.shouldShowJobCard(state: status.state) else { return nil }
        guard model.showJobActions else { return nil }
        return status.state
    }

    private func showsLinksRow(for presentation: Presentation) -> Bool {
        guard isContentOrDisconnected(presentation) else { return false }
        return Self.shouldRenderLinksRow(
            showPrusaLinkButton: model.showPrusaLinkButton,
            showPrusaConnectButton: model.showPrusaConnectButton
        )
    }

    private func isContentOrDisconnected(_ presentation: Presentation) -> Bool {
        switch presentation {
        case .content, .disconnected:
            true
        case .unconfigured, .loading:
            false
        }
    }

    /// Whether rows 2 (file name + thumbnail) and 3 (progress bar) should
    /// render given the current printer state. The caller still has to check
    /// that a `lastJob` is cached; this helper covers the state side only so
    /// it can be unit-tested without standing up a full `AppModel`.
    nonisolated static func shouldShowJobCard(state: PrinterState) -> Bool {
        switch state {
        case .printing, .paused, .attention, .finished:
            true
        case .idle, .ready, .busy, .stopped, .error:
            false
        }
    }

    /// Whether the "Open PrusaLink" button should be enabled. Disabled when
    /// the printer URL is missing OR the printer is currently in the
    /// disconnected state, since the local web UI is then unreachable.
    nonisolated static func shouldEnablePrusaLink(
        printerBaseURL: String,
        isDisconnected: Bool
    ) -> Bool {
        let trimmed = printerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isDisconnected
    }

    /// Whether the LinksRow should render at all, given the user's
    /// "Show PrusaLink button" and "Show Prusa Connect button" toggles.
    /// Returns false only when both toggles are OFF, so callers should omit
    /// the row entirely in that case.
    nonisolated static func shouldRenderLinksRow(
        showPrusaLinkButton: Bool,
        showPrusaConnectButton: Bool
    ) -> Bool {
        showPrusaLinkButton || showPrusaConnectButton
    }
}

extension DropdownView {
    /// Resolves the URL the PrusaConnect button should open. With a non-empty
    /// trimmed UUID, deep-links to the printer's dashboard; otherwise falls
    /// back to the generic cloud entry point. Carved out as `nonisolated`
    /// static so it is unit-testable without standing up a `MenuBarController`.
    nonisolated static func prusaConnectURL(uuid: String) -> URL? {
        let trimmed = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = trimmed.isEmpty
            ? "https://connect.prusa3d.com"
            : "https://connect.prusa3d.com/printer/\(trimmed)/dashboard"
        return URL(string: urlString)
    }
}

// MARK: - State body builders

extension DropdownView {
    var unconfiguredCard: some View {
        UnconfiguredCard(
            accent: model.accent,
            customHex: model.customAccentHex,
            onConfigure: onConfigurePrinter
        )
    }

    var disconnectedCard: some View {
        VStack(spacing: Theme.Spacing.med) {
            Image("PrusaCoreOne")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
            HStack(spacing: Theme.Spacing.sml) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 14, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.Palette.stateAmber)
                Text(L10n.t("dropdown.unreachable.title"))
                    .font(.prusaBody.weight(.semibold))
            }
            Text(L10n.t("dropdown.unreachable.message"))
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .prusaCard()
    }

    var loadingCard: some View {
        VStack(spacing: Theme.Spacing.med) {
            Image("PrusaCoreOne")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
            HStack(spacing: Theme.Spacing.sml) {
                ProgressView().controlSize(.small)
                Text(L10n.t("dropdown.loading"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .prusaCard()
    }

    func contentBody(for status: PrinterStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.med) {
            if let job = model.lastJob, Self.shouldShowJobCard(state: status.state) {
                JobCard(
                    job: job,
                    status: status,
                    thumbnail: model.lastThumbnail,
                    showRemainingTime: model.showRemainingTime,
                    progressResetToken: model.popoverShowToken,
                    progressBarStyle: model.progressBarStyle,
                    isPopoverVisible: model.popoverVisible
                )
                // On finish, force Prusa green so the hero card itself
                // acknowledges completion regardless of the user accent.
                .environment(
                    \.brandAccent,
                    status.state == .finished ? .green : model.accent
                )
            }

            if model.showTemperatures, status.nozzleTemperature != nil || status.bedTemperature != nil {
                temperaturesGrid(status: status)
            }

            // Mount the camera tile only while the popover is on screen.
            // SwiftUI removing it on close triggers
            // `CameraPlayerView.dismantleNSView` -> AVPlayer pause/clear.
            // The popover delegate additionally stops go2rtc, so neither
            // CPU nor camera bandwidth is used while the menu is closed.
            if dropdownVisible, model.buddyCameraEnabled, let rtsp = nonEmpty(model.rtspURL) {
                CameraTile(urlString: rtsp, model: model, onZoom: { onZoomCamera(.buddy, $0) })
            }

            if shouldRenderGenericCameraTile {
                GenericCameraTile(
                    config: model.genericCameraConfig,
                    model: model,
                    onZoom: { onZoomCamera(.generic, $0) }
                )
            }

            if hasVisibleSecondCustomActionsRow {
                CustomActionsRow(
                    leftConfig: customConfig(.rowSecondLeft),
                    rightConfig: customConfig(.rowSecondRight),
                    leftVisible: isCustomVisible(.rowSecondLeft),
                    rightVisible: isCustomVisible(.rowSecondRight),
                    leftFeedback: customActionFeedback[.rowSecondLeft] ?? .idle,
                    rightFeedback: customActionFeedback[.rowSecondRight] ?? .idle,
                    onRunLeft: { runCustomAction(.rowSecondLeft) },
                    onRunRight: { runCustomAction(.rowSecondRight) }
                )
            }

            LiveMetricsCard(rows: extraRows(for: status))
        }
    }
}

private extension DropdownView {
    /// True whenever the dropdown content is on screen -- either inside the
    /// transient popover or inside the detached floating window.
    var dropdownVisible: Bool {
        model.popoverVisible || model.detachedWindowVisible
    }

    var maxPopoverHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(200, screenHeight - Theme.Layout.popoverScreenMargin)
    }

    private var presentationKind: PresentationKind {
        switch presentation {
        case .unconfigured: .unconfigured
        case .disconnected: .disconnected
        case .loading: .loading
        case .content: .content
        }
    }

    var shouldRenderGenericCameraTile: Bool {
        dropdownVisible
            && model.genericCameraConfig.enabled
            && model.genericCameraConfig.hasUsableSource
    }
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
