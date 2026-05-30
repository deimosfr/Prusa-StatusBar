import SwiftUI

/// Embedded camera preview shown in the dropdown when an RTSP URL is
/// configured. libvlc (VLCKit) decodes the RTSP feed directly in-process,
/// so there is no transmux helper and no localhost server. Production and
/// prototype builds share the same SwiftUI surface; prototype renders a
/// static placeholder.
///
/// The tile is clickable across its full bounds: clicking invokes
/// `onZoom`, which the dropdown wires to a `CameraQuickLookWindowController`
/// to open a dedicated, resizable popup window.
struct CameraTile: View {
    let urlString: String
    let model: AppModel
    var onZoom: ((CameraQuickLookSource) -> Void)?

    private let kind: CameraTileKind = .buddy

    /// Sticky readiness flag. Flips true once the player reports the first
    /// `.readyToPlay` and stays true for the lifetime of this view so the
    /// spinner does not flap back on during transient stalls. A new RTSP
    /// URL resets it via the `.id(urlString)` view-identity bump.
    @State private var isReady: Bool = false
    /// Native video aspect (width / height) reported by the player. Nil
    /// until the first frame is decoded. Used to size the tile to the
    /// actual video so AVPlayerLayer does not add black bars.
    @State private var videoAspect: CGFloat?

    var body: some View {
        ZStack {
            Color.black
            content
            if showsLoadingSpinner {
                loadingOverlay
            }
        }
        .modifier(CameraTileFrame(
            model: model,
            kind: kind,
            isReady: !showsLoadingSpinner,
            videoAspect: videoAspect
        ))
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

    private var loadingOverlay: some View {
        ProgressView()
            .controlSize(.small)
            .progressViewStyle(.circular)
            .tint(.white)
            .allowsHitTesting(false)
    }

    /// Only show the spinner while we are actively waiting for the live
    /// stream. In prototype mode and in the "invalid URL" branch, the
    /// content view already conveys state, so a spinner on top would be
    /// noise.
    private var showsLoadingSpinner: Bool {
        #if PROTOTYPE_MODE
            return false
        #else
            return resolveRequest() != nil && !isReady
        #endif
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
            if let request = resolveRequest() {
                CameraPlayerView(
                    request: request,
                    onReady: { isReady = true },
                    onPresentationSize: { size in
                        guard size.height > 0 else { return }
                        videoAspect = size.width / size.height
                    }
                )
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
            return resolveRequest().map(CameraQuickLookSource.stream)
        #endif
    }

    #if !PROTOTYPE_MODE
        private func resolveRequest() -> CameraStreamRequest? {
            guard case let .valid(rtspURL) = RTSPURLValidator.validate(urlString) else {
                return nil
            }
            // Buddy camera always forces RTSP-over-TCP: the firmware's UDP
            // path is unreliable on restricted networks.
            return CameraStreamRequest(url: rtspURL, transport: .tcp)
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
    /// When `false`, ignore any cached video height and fall back to the
    /// loading-state placeholder. Avoids a giant black rectangle while the
    /// player is still warming up after the cache was populated by an
    /// earlier successful render.
    var isReady: Bool = true
    /// Native video aspect (width / height) reported by AVPlayerItem
    /// once decoding starts. When set, the tile is sized to that aspect
    /// so AVPlayerLayer's `.resizeAspect` fills exactly with no
    /// letterbox/pillarbox bars. Falls back to cached or placeholder
    /// height when nil.
    var videoAspect: CGFloat?

    /// Container width measured in the aspect branch. Used to derive the
    /// tile height as `width / aspect` so the tile is always pinned to full
    /// width instead of being shrunk and centered by `.aspectRatio(.fit)`
    /// when the popover squeezes the available height.
    @State private var measuredWidth: CGFloat?

    func body(content: Content) -> some View {
        if !isReady {
            content.frame(maxWidth: .infinity, minHeight: cameraTilePlaceholderMinHeight)
        } else if let aspect = videoAspect, aspect > 0 {
            content
                .frame(maxWidth: .infinity)
                .frame(height: aspectHeight(for: aspect))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CameraTileWidthPreference.self,
                            value: geo.size.width
                        )
                    }
                )
                .onPreferenceChange(CameraTileWidthPreference.self) { measuredWidth = $0 }
        } else if let cached = model.cameraTileHeights[kind] {
            content.frame(maxWidth: .infinity, minHeight: cached, maxHeight: cached)
        } else {
            content.frame(maxWidth: .infinity, minHeight: cameraTilePlaceholderMinHeight)
        }
    }

    /// Height for the aspect branch. Before the width is measured, fall back
    /// to the cached or placeholder height so the tile does not collapse to
    /// zero on the first layout pass.
    private func aspectHeight(for aspect: CGFloat) -> CGFloat {
        guard let width = measuredWidth, width > 0 else {
            return model.cameraTileHeights[kind] ?? cameraTilePlaceholderMinHeight
        }
        return (width / aspect).rounded()
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

/// Carries the camera tile's measured container width up to `CameraTileFrame`
/// so the aspect branch can derive height as `width / aspect`, pinning the
/// tile to full width instead of letting `.aspectRatio(.fit)` shrink it.
struct CameraTileWidthPreference: PreferenceKey {
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
