import AVFoundation
import AVKit
import SwiftUI

/// Embedded camera preview shown in the dropdown when an RTSP URL is
/// configured. AVKit cannot speak RTSP directly, so a bundled `go2rtc`
/// subprocess transmuxes the RTSP feed into HLS on `127.0.0.1:1984` and
/// AVPlayer plays the HLS endpoint. Production and prototype builds share
/// the same SwiftUI surface; prototype renders a static placeholder.
///
/// The tile is clickable across its full bounds: clicking invokes
/// `onZoom`, which the dropdown wires to a `CameraQuickLookWindowController`
/// to open a dedicated, resizable popup window.
struct CameraTile: View {
    let urlString: String
    let model: AppModel
    var onZoom: ((CameraQuickLookSource) -> Void)?

    private let kind: CameraTileKind = .buddy

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
        .id(urlString)
    }

    @ViewBuilder
    private var content: some View {
        #if PROTOTYPE_MODE
            VStack(spacing: 6) {
                Image(systemName: "video")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text(L10n.t("dropdown.camera.preview"))
                    .font(.prusaCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        #else
            if let hlsURL = resolveHLSURL() {
                CameraPlayerView(url: hlsURL)
            } else {
                Text(L10n.t("error.rtsp.invalid"))
                    .font(.prusaCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        #endif
    }

    @ViewBuilder
    private var zoomOverlay: some View {
        if let onZoom, let source = currentSource() {
            CameraTileZoomButton { onZoom(source) }
        }
    }

    /// Source the popup should render. Mirrors what `content` is currently
    /// showing so the popup stays in sync with the tile.
    private func currentSource() -> CameraQuickLookSource? {
        #if PROTOTYPE_MODE
            return .prototype(label: L10n.t("dropdown.camera.preview"), systemImage: "video")
        #else
            return resolveHLSURL().map(CameraQuickLookSource.hls)
        #endif
    }

    #if !PROTOTYPE_MODE
        private func resolveHLSURL() -> URL? {
            guard case let .valid(rtspURL) = RTSPURLValidator.validate(urlString) else {
                return nil
            }
            return GoRTCService.shared.hlsURL(forRTSP: rtspURL.absoluteString)
        }
    #endif
}

/// Default loading-state minimum height for a camera tile when no cached
/// height is available yet for this online session.
let cameraTilePlaceholderMinHeight: CGFloat = 180

/// Sizes a camera tile to its cached height when available, otherwise
/// falls back to the loading-state minimum height. Pinning the height
/// once a real frame has been measured keeps the tile from reflowing on
/// subsequent reopens while the camera pipeline warms up.
struct CameraTileFrame: ViewModifier {
    let model: AppModel
    let kind: CameraTileKind

    func body(content: Content) -> some View {
        if let cached = model.cameraTileHeights[kind] {
            content.frame(maxWidth: .infinity, minHeight: cached, maxHeight: cached)
        } else {
            content.frame(maxWidth: .infinity, minHeight: cameraTilePlaceholderMinHeight)
        }
    }
}

/// Carries the rendered camera tile height up the view hierarchy so the
/// containing tile can store it in `AppModel.cameraTileHeights`. Only
/// ready-state branches (decoded image / live player) emit values; the
/// loading spinner branch never sets the preference, so the cache only
/// records real-frame heights.
struct CameraTileHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// Helper used by camera tiles to commit a measured height into the
/// shared cache. Centralized so both Buddy and Generic tiles apply the
/// same idempotent guard (`>0` and changed) and so tests can exercise
/// the same code path.
@MainActor
enum CameraTileSizeCache {
    static func commit(model: AppModel, kind: CameraTileKind, height: CGFloat) {
        guard height > 0 else { return }
        if model.cameraTileHeights[kind] == height { return }
        model.cameraTileHeights[kind] = height
    }
}

/// Transparent button overlay that fills the parent tile and routes
/// clicks to the Quick Look popup. Uses `.contentShape(Rectangle())` so
/// the entire bounds are hit-testable, and pushes a `pointingHand`
/// cursor on hover so the affordance is discoverable.
struct CameraTileZoomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("dropdown.camera.quicklook.open"))
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
