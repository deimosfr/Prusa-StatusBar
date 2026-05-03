import AppKit
import SwiftUI

/// Identifies what content the Quick Look popup should render. Built by
/// the dropdown tile at click time from the same URL resolution code the
/// tile itself uses, so the popup mirrors whatever the tile is currently
/// showing.
public enum CameraQuickLookSource: Equatable {
    /// Live HLS stream. In prototype builds the tile passes
    /// `.prototype(...)` instead, so this case never reaches non-network
    /// code paths in prototype mode.
    case hls(URL)
    #if !PROTOTYPE_MODE
        case still(URL, GenericCameraConfig)
    #endif
    case prototype(label: String, systemImage: String)
}

/// SwiftUI content of the Quick Look popup `NSWindow`. Uses the same
/// playback components as the dropdown tiles, but without the tile size
/// cache so the content can fill the freely resizable window.
struct CameraQuickLookView: View {
    let source: CameraQuickLookSource

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch source {
        case let .hls(url):
            #if PROTOTYPE_MODE
                placeholder(label: L10n.t("dropdown.camera.preview"), systemImage: "video")
            #else
                CameraPlayerView(url: url)
            #endif
        #if !PROTOTYPE_MODE
            case let .still(url, config):
                StillImagePollerView(url: url, config: config, emitsHeightPreference: false)
        #endif
        case let .prototype(label, systemImage):
            placeholder(label: label, systemImage: systemImage)
        }
    }

    private func placeholder(label: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text(label)
                .font(.prusaBody)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
