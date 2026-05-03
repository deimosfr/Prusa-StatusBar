import AppKit
import Foundation

/// Pure presentation logic, given a `PrinterStatus` (or its absence), compute
/// the icon source, tint, and short label that the menu bar should show.
///
/// Spec reference: `openspec/specs/menu-bar-ui/spec.md`.
public enum StatusPresenter {
    /// Source of the icon shown in the menu bar. SF Symbols are tinted via
    /// `NSImage.SymbolConfiguration(paletteColors:)`; bundled assets are
    /// rendered as template images so macOS tints them with the menu-bar
    /// foreground color.
    public enum IconSource: Equatable {
        case symbol(String)
        case asset(String)
        /// Tiny clickable template circle, sized to occupy minimal menu-bar
        /// width while keeping the status item hit-testable. Used for the
        /// `.minimal` disconnected-icon style.
        case minimalDot
        /// Fully empty button image (1pt transparent placeholder). The
        /// status item collapses to a thin invisible strip but remains
        /// clickable. Used for the `.none` disconnected-icon style.
        case empty
        /// User-chosen emoji rendered as a colored (non-template) image.
        /// Used for the `.emoji` disconnected-icon style.
        case emoji(String)
        /// Menu-bar marker for the `.printing` state. The controller decides
        /// whether to play a bounded burst animation (on entry into
        /// printing or on launch-while-printing) or to render the settled
        /// rest-pose keyframe directly.
        case animatedPrinting
    }

    public struct MenuBarPresentation: Equatable {
        public let icon: IconSource
        public let tint: NSColor?
        public let label: String

        public init(icon: IconSource, tint: NSColor?, label: String) {
            self.icon = icon
            self.tint = tint
            self.label = label
        }
    }

    public enum AssetName {
        public static let idle = "IconIdle"
        public static let printing = "IconPrinting"
        /// Settled (non-animated) printing glyph for the menu bar. Sourced
        /// from keyframe 10 of the printing animation so the rest pose
        /// matches the wind-down end of the burst sequence.
        public static let printingStatic = "IconPrinting_10"
        public static let paused = "IconPaused"
        public static let finished = "IconFinished"
        public static let stopped = "IconStopped"
        public static let busy = "IconBusy"
        public static let attention = "IconAttention"
        public static let disconnected = "IconDisconnected"
    }

    /// Canonical asset-name mapping shared between the menu bar
    /// (`StatusPresenter.present`) and the popover `StatusPill` so the two
    /// surfaces always render the same glyph for a given state.
    public static func assetName(
        for state: PrinterState,
        isDisconnected: Bool = false,
        isConfigured: Bool = true
    ) -> String {
        guard isConfigured else { return AssetName.idle }
        if isDisconnected { return AssetName.disconnected }
        return switch state {
        case .printing: AssetName.printing
        case .paused: AssetName.paused
        case .finished: AssetName.finished
        case .stopped: AssetName.stopped
        case .busy: AssetName.busy
        case .attention, .error: AssetName.attention
        case .idle, .ready: AssetName.idle
        }
    }

    public static func present(
        status: PrinterStatus?,
        isDisconnected: Bool,
        isConfigured: Bool,
        showRemainingTime: Bool,
        showPercentage: Bool,
        disconnectedIconStyle: DisconnectedIconStyle = .default,
        disconnectedIconEmoji: String = UserPreferences.disconnectedIconEmojiDefault
    ) -> MenuBarPresentation {
        guard isConfigured else {
            return MenuBarPresentation(icon: .asset(AssetName.idle), tint: nil, label: "")
        }
        if isDisconnected {
            let icon = disconnectedIcon(
                style: disconnectedIconStyle,
                emoji: disconnectedIconEmoji
            )
            return MenuBarPresentation(icon: icon, tint: nil, label: "")
        }
        guard let status else {
            return MenuBarPresentation(icon: .asset(AssetName.idle), tint: nil, label: "")
        }

        let asset = assetName(for: status.state)
        switch status.state {
        case .idle, .ready, .stopped, .busy:
            return MenuBarPresentation(icon: .asset(asset), tint: nil, label: "")
        case .finished:
            let finishedLabel = showPercentage ? "100%" : ""
            return MenuBarPresentation(icon: .asset(asset), tint: nil, label: finishedLabel)
        case .printing:
            let label = makeLabel(
                status: status,
                showRemainingTime: showRemainingTime,
                showPercentage: showPercentage
            )
            return MenuBarPresentation(icon: .animatedPrinting, tint: nil, label: label)
        case .paused, .attention, .error:
            let label = makeLabel(
                status: status,
                showRemainingTime: showRemainingTime,
                showPercentage: showPercentage
            )
            return MenuBarPresentation(icon: .asset(asset), tint: nil, label: label)
        }
    }

    /// Picks the icon source for the disconnected state per the user's
    /// chosen style. Falls back to the default asset when the user picked
    /// `.emoji` but the stored emoji is empty (defensive: the
    /// `UserPreferences` accessor already substitutes the default, but a
    /// manual `defaults write` could still produce a blank value).
    static func disconnectedIcon(
        style: DisconnectedIconStyle,
        emoji: String
    ) -> IconSource {
        switch style {
        case .default:
            return .asset(AssetName.disconnected)
        case .minimal:
            return .minimalDot
        case .none:
            return .empty
        case .emoji:
            let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .asset(AssetName.disconnected)
            }
            return .emoji(trimmed)
        }
    }

    static func makeLabel(
        status: PrinterStatus,
        showRemainingTime: Bool,
        showPercentage: Bool
    ) -> String {
        var parts: [String] = []
        if showPercentage, let progress = status.progress {
            parts.append("\(Int((progress * 100).rounded()))%")
        }
        if showRemainingTime, let remaining = status.timeRemaining, remaining > 0 {
            parts.append(formatCompactDuration(seconds: Int(remaining.rounded())))
        }
        return parts.joined(separator: " ")
    }

    /// Reused across every popover render. `DateFormatter` is documented as
    /// thread-safe for read after configuration on Apple platforms, so a
    /// single shared instance avoids per-call locale resolution.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Formats a `Date` as a localized short clock-time string (e.g. "14:32"
    /// or "2:32 PM") for the ETA chip in the popover.
    static func formatClockTime(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// Formats the ETA chip text. Tiers, by calendar-day distance from `now`:
    ///   0 (same day, or ETA already past) -> `"13:52"`
    ///   1...6                             -> `"Mon 13:52"` (localized)
    ///   >= 7                              -> `"+8d 13:52"`
    /// Day distance is computed with `calendar.startOfDay(for:)` on both
    /// dates so that crossing midnight by even a minute counts as a different
    /// day. `calendar` and `now` are injected so the helper is fully
    /// deterministic under test.
    static func formatEtaPill(
        eta: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let nowDay = calendar.startOfDay(for: now)
        let etaDay = calendar.startOfDay(for: eta)
        let dayDiff = calendar.dateComponents([.day], from: nowDay, to: etaDay).day ?? 0
        let clock = formatClockTime(eta)
        if dayDiff <= 0 {
            return clock
        }
        if dayDiff <= 6 {
            let formatter = DateFormatter()
            formatter.locale = calendar.locale ?? .autoupdatingCurrent
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEE"
            return "\(formatter.string(from: eta)) \(clock)"
        }
        return "+\(dayDiff)d \(clock)"
    }

    /// Formats a number of seconds into a compact `[Xd][Yh][Zm][Ws]` string,
    /// dropping zero-valued leading units. Examples:
    ///   3661 -> "1h1m"
    ///   90   -> "1m30s"
    ///   45   -> "45s"
    static func formatCompactDuration(seconds: Int) -> String {
        if seconds <= 0 {
            return "0s"
        }
        let day = 86400
        let hour = 3600
        let minute = 60

        var remaining = seconds
        var parts: [String] = []

        let days = remaining / day
        if days > 0 {
            parts.append("\(days)d")
            remaining -= days * day
        }
        let hours = remaining / hour
        if hours > 0 || !parts.isEmpty {
            if hours > 0 {
                parts.append("\(hours)h")
            }
            remaining -= hours * hour
        }
        let minutes = remaining / minute
        if minutes > 0 || (!parts.isEmpty && parts.count < 2) {
            if minutes > 0 {
                parts.append("\(minutes)m")
            }
            remaining -= minutes * minute
        }
        if parts.isEmpty {
            parts.append("\(remaining)s")
        }
        return parts.prefix(2).joined()
    }
}
