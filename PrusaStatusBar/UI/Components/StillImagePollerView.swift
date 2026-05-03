import AppKit
import SwiftUI

#if !PROTOTYPE_MODE
    /// Hosts a periodic `URLSession` GET against the still-image URL and
    /// renders the latest frame. Used both inside the dropdown
    /// `GenericCameraTile` and inside the camera Quick Look popup window.
    /// The fetcher is created and torn down with the view's lifecycle so
    /// polling stops the moment the host disappears.
    ///
    /// `emitsHeightPreference` controls whether the rendered height bubbles
    /// up via `CameraTileHeightPreference`. Tiles want it; the freely
    /// resizable popup window does not, since the tile size cache is
    /// irrelevant there.
    struct StillImagePollerView: View {
        let url: URL
        let config: GenericCameraConfig
        var emitsHeightPreference: Bool = true

        @State private var image: NSImage?
        @State private var lastError: String?
        @State private var fetcher: GenericCameraStillFetcher?

        var body: some View {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(heightPreferenceReader)
                } else if let lastError {
                    Text(lastError)
                        .font(.prusaCaption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .id(url.absoluteString)
            .onAppear { startFetcher() }
            .onDisappear { fetcher?.stop() }
            .onChange(of: url) { _, _ in startFetcher() }
            .onChange(of: config.framerate) { _, _ in fetcher?.apply(config) }
            .onChange(of: config.contentType) { _, _ in fetcher?.apply(config) }
        }

        @ViewBuilder
        private var heightPreferenceReader: some View {
            if emitsHeightPreference {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CameraTileHeightPreference.self,
                        value: proxy.size.height
                    )
                }
            } else {
                Color.clear
            }
        }

        @MainActor
        private func startFetcher() {
            fetcher?.stop()
            let new = GenericCameraStillFetcher { update in
                switch update {
                case let .image(nsImage):
                    image = nsImage
                    lastError = nil
                case let .failure(reason):
                    if image == nil { lastError = reason }
                }
            }
            fetcher = new
            new.start(config: config)
        }
    }
#endif
