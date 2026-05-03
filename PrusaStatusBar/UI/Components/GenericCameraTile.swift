import AppKit
import SwiftUI

/// Second-camera tile rendered directly below the Buddy `CameraTile` in
/// the dropdown. Picks between live stream playback (RTSP / HTTP MJPEG via
/// the bundled go2rtc helper) and still-image polling based on which URL
/// the user configured. On stream failure (after the player's retry
/// budget exhausts) the tile auto-falls-back to still-image polling when
/// a still URL is configured.
struct GenericCameraTile: View {
    let config: GenericCameraConfig
    let model: AppModel
    var onZoom: ((CameraQuickLookSource) -> Void)?

    private let kind: CameraTileKind = .generic

    @State private var fallbackToStill: Bool = false

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .modifier(CameraTileFrame(model: model, kind: kind))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
        )
        .overlay(zoomOverlay)
        .onPreferenceChange(CameraTileHeightPreference.self) { newValue in
            Task { @MainActor in
                CameraTileSizeCache.commit(model: model, kind: kind, height: newValue)
            }
        }
        .id(tileIdentity)
        .onChange(of: tileIdentity) { _, _ in
            // Reset fallback whenever the active source changes; the new
            // stream gets a fresh retry budget.
            fallbackToStill = false
        }
    }

    @ViewBuilder
    private var zoomOverlay: some View {
        if let onZoom, let source = currentSource() {
            CameraTileZoomButton { onZoom(source) }
        }
    }

    /// Source the popup should render. Mirrors what the live tile is
    /// currently showing, including the stream-to-still fallback flip.
    private func currentSource() -> CameraQuickLookSource? {
        #if PROTOTYPE_MODE
            return .prototype(label: L10n.t("dropdown.generic_camera.preview"), systemImage: "video.badge.plus")
        #else
            if shouldRenderStream, let hlsURL = resolveStreamHLSURL() {
                return .hls(hlsURL)
            }
            if let stillURL = config.resolvedStillImageURL() {
                return .still(stillURL, config)
            }
            return nil
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if PROTOTYPE_MODE
            VStack(spacing: 6) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text(L10n.t("dropdown.generic_camera.preview"))
                    .font(.prusaCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        #else
            liveContent
        #endif
    }

    #if !PROTOTYPE_MODE
        @ViewBuilder
        private var liveContent: some View {
            if shouldRenderStream, let hlsURL = resolveStreamHLSURL() {
                CameraPlayerView(
                    url: hlsURL,
                    onFailureExhausted: handleStreamFailure
                )
            } else if let stillURL = config.resolvedStillImageURL() {
                StillImagePollerView(url: stillURL, config: config)
            } else {
                Text(L10n.t("error.rtsp.invalid"))
                    .font(.prusaCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }

        private var shouldRenderStream: Bool {
            if fallbackToStill, config.resolvedStillImageURL() != nil { return false }
            if case .stream = config.preferredMode { return true }
            return false
        }

        private func resolveStreamHLSURL() -> URL? {
            guard let resolved = config.resolvedStreamURL() else { return nil }
            return GoRTCService.shared.hlsURL(forGenericStream: resolved.absoluteString)
        }

        @MainActor
        private func handleStreamFailure() {
            // Only meaningful when there is something to fall back to.
            if config.resolvedStillImageURL() != nil {
                fallbackToStill = true
            }
        }
    #endif

    /// Identity that changes whenever the user-visible source switches:
    /// stream URL change, still URL change, or fallback flip.
    private var tileIdentity: String {
        "\(config.streamURL)|\(config.stillImageURL)|\(fallbackToStill)"
    }
}
