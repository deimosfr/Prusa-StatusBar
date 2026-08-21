import AppKit

/// Drives the bounded "printing" burst animation on the `NSStatusItem`
/// button by frame-swapping through pre-rendered keyframe assets
/// (`IconPrinting_00` ... `IconPrinting_23`). NSImage cannot animate the
/// SMIL inside a single SVG, so frame-swap is the only path that
/// produces motion in the menu bar. Plays exactly `cycleCount` cycles
/// (2 by default, 1.6s total at 0.8s/cycle) then settles on the
/// `IconPrintingStatic` asset.
///
/// The animator is a one-shot per `play(...)` call. Calling `play` while
/// a previous burst is in flight cancels the old one. `cancel()` halts
/// mid burst and leaves whatever image was last applied to the button.
@MainActor
public final class PrintingIconAnimator {
    public static let cycleDuration: Double = 2.4
    public static let cycleCount: Int = 2
    /// Asset names for the 24 keyframes that make up one full animation
    /// cycle. The author (the user) supplied these as separate SVGs;
    /// they are wired into `Assets.xcassets` as template imagesets.
    public static let frameAssetNames: [String] = (0 ..< 24)
        .map { String(format: "IconPrinting_%02d", $0) }

    /// Number of leading keyframes (`IconPrinting_00` ... `IconPrinting_08`)
    /// that play after the looped cycles, immediately before the menu bar
    /// settles on `IconPrintingStatic` (whose visual matches frame 10).
    /// Gives the cup a smooth wind-down into the rest pose instead of
    /// snapping mid-cycle to the static image.
    public static let trailingFrameCount: Int = 9

    /// Per-frame interval (seconds) derived from `cycleDuration` and the
    /// number of keyframes. Exposed so `PrintingIconAnimatorTests` can
    /// assert the burst lines up with the spec's cadence.
    public static var frameInterval: Double {
        cycleDuration / Double(frameAssetNames.count)
    }

    /// Effective frame rate. Exposed for parity with the legacy bake API
    /// the tests asserted against.
    public static var frameRate: Double {
        Double(frameAssetNames.count) / cycleDuration
    }

    /// Menu-bar icon size. Matches the value used for the bundled asset
    /// path in `MenuBarController.makeImage(for:)` so the burst frames
    /// and the settled `IconPrintingStatic` stay visually identical.
    public static let iconSize = NSSize(width: 17, height: 17)

    private var task: Task<Void, Never>?

    public init() {}

    public var isPlaying: Bool {
        task != nil
    }

    /// Plays the burst on the given button. The previous burst (if any)
    /// is cancelled. `completion` fires after the static image is
    /// applied.
    public func play(
        on button: NSStatusBarButton,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        cancel()
        let frames = Self.bakeFrames()
        let settled = Self.settledImage()
        let interval = Self.frameInterval
        let intervalNanos = UInt64(interval * 1_000_000_000)
        let weakButton = WeakButton(button)

        task = Task { @MainActor [weak self] in
            for frame in frames {
                if Task.isCancelled {
                    return
                }
                weakButton.value?.image = frame
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
            if Task.isCancelled {
                return
            }
            weakButton.value?.image = settled
            completion()
            self?.task = nil
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Cache for `bakeFrames()`. The full 57-image sequence is computed
    /// once on first burst and reused across every subsequent burst, so
    /// `play(on:)` does not pay the asset-loading cost on each call.
    private static var cachedFrames: [NSImage]?

    /// Loads the full burst sequence as template `NSImage`s sized to the
    /// menu-bar icon. The sequence is:
    ///
    ///   - `cycleCount` consecutive 24-keyframe cycles (continuous loop), then
    ///   - the first `trailingFrameCount` keyframes (frames 0 through 8) as
    ///     a smooth wind-down so the motion lands gracefully at frame 10's
    ///     pose, which is the same visual as `IconPrintingStatic`.
    static func bakeFrames() -> [NSImage] {
        if let cached = cachedFrames {
            return cached
        }
        var frames: [NSImage] = []
        frames.reserveCapacity(frameAssetNames.count * cycleCount + trailingFrameCount)
        for _ in 0 ..< cycleCount {
            for name in frameAssetNames {
                frames.append(loadAssetImage(named: name))
            }
        }
        for index in 0 ..< trailingFrameCount {
            frames.append(loadAssetImage(named: frameAssetNames[index]))
        }
        cachedFrames = frames
        return frames
    }

    static func loadAssetImage(named name: String) -> NSImage {
        let image = NSImage(named: name) ?? NSImage(size: iconSize)
        image.isTemplate = true
        image.size = iconSize
        image.accessibilityDescription = "Prusa StatusBar"
        return image
    }

    /// The settled image after the burst. Sourced from the bundled
    /// `IconPrintingStatic` template asset so the menu bar matches the
    /// rest of the icon family at rest.
    static func settledImage() -> NSImage {
        let image = NSImage(named: StatusPresenter.AssetName.printingStatic) ?? NSImage(size: iconSize)
        image.isTemplate = true
        image.size = iconSize
        image.accessibilityDescription = "Prusa StatusBar"
        return image
    }
}

/// Wraps a weak `NSStatusBarButton` reference in a class so the
/// animation `Task` can capture it without crossing the Sendable boundary
/// on `NSStatusBarButton` (which is `@MainActor`-isolated, not
/// `Sendable`).
@MainActor
private final class WeakButton {
    weak var value: NSStatusBarButton?
    init(_ value: NSStatusBarButton) {
        self.value = value
    }
}
