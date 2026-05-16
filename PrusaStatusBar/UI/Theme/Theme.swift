import AppKit
import SwiftUI

/// Visual design tokens for the popover and Preferences surfaces.
/// Colors resolve against the asset catalog so light/dark adaptation is
/// handled by the system.
public enum Theme {
    /// User-selectable brand accent.
    public enum Accent: String, CaseIterable, Sendable {
        case orange
        case orangeLegacy = "orange_legacy"
        case green
        case custom

        /// Human-readable name shown in the picker tooltip.
        public var displayName: String {
            switch self {
            case .orange: "Prusa Orange"
            case .orangeLegacy: "Old Prusa Orange"
            case .green: "Prusa Pro"
            case .custom: "Custom"
            }
        }
    }

    /// Alpha applied on top of the parsed custom accent color to derive its
    /// muted variant. Mirrors the 0.18 alpha shipped on `BrandOrangeMuted` /
    /// `BrandGreenMuted` colorsets.
    public static let customAccentMutedAlpha: Double = 0.18

    public enum Palette {
        public static func brand(_ accent: Accent) -> Color {
            brand(accent, customHex: "")
        }

        public static func brand(_ accent: Accent, customHex: String) -> Color {
            switch accent {
            case .orange: Color("BrandOrange")
            case .orangeLegacy: Color("BrandOrangeLegacy")
            case .green: Color("BrandGreen")
            case .custom: Color(hex: customHex) ?? Color("BrandOrange")
            }
        }

        public static func brandMuted(_ accent: Accent) -> Color {
            brandMuted(accent, customHex: "")
        }

        public static func brandMuted(_ accent: Accent, customHex: String) -> Color {
            switch accent {
            case .orange: Color("BrandOrangeMuted")
            case .orangeLegacy: Color("BrandOrangeLegacyMuted")
            case .green: Color("BrandGreenMuted")
            case .custom:
                (Color(hex: customHex) ?? Color("BrandOrange"))
                    .opacity(Theme.customAccentMutedAlpha)
            }
        }

        public static let surfaceElevated = Color("SurfaceElevated")
        public static let hairline = Color("Hairline")

        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
        public static let textTertiary = Color.secondary.opacity(0.7)

        public static let stateGreen = Color("BrandGreen")
        public static let stateRed = Color.red
        public static let stateAmber = Color.orange
        public static let stateYellow = Color.yellow
        public static let statePink = Color.pink
        public static let stateGrey = Color("BrandGrey")
        public static let stateNeutral = Color("BrandGrey")

        public static let statePrintingOrange = Color("BrandOrange")
        public static let statePrintingOrangeMuted = Color("BrandOrangeMuted")
        public static let stateCoolingBlue = Color.blue
    }

    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let sml: CGFloat = 8
        public static let med: CGFloat = 12
        public static let lrg: CGFloat = 16
        public static let xlg: CGFloat = 20
    }

    public enum Radius {
        public static let card: CGFloat = 12
        public static let thumbnail: CGFloat = 10
        public static let pill: CGFloat = 999
        public static let progressBar: CGFloat = 4
    }

    public enum Layout {
        public static let popoverWidth: CGFloat = 360
        public static let popoverPadding: CGFloat = 16
        public static let popoverFooterBottomPadding: CGFloat = 8
        /// Vertical inset reserved on top of the active screen's `visibleFrame`
        /// height when bounding the popover. Covers the popover arrow and a
        /// small safety gap so the popover never sits flush against the dock.
        public static let popoverScreenMargin: CGFloat = 48
        public static let cardPadding: CGFloat = 12
        public static let heroThumbnail: CGFloat = 64
        public static let progressBarHeight: CGFloat = 8
        public static let tempRingSize: CGFloat = 36
    }

    public enum Hairline {
        public static let width: CGFloat = 0.5
    }
}

public extension Font {
    static let prusaTitle = Font.system(size: 15, weight: .semibold)
    static let prusaSectionHeader = Font.system(size: 10, weight: .medium).leading(.tight)
    static let prusaBody = Font.system(size: 13)
    static let prusaCaption = Font.system(size: 11)
    static let prusaCaptionStrong = Font.system(size: 11, weight: .medium)
    static let prusaMetric = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let prusaMetricSmall = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let prusaPill = Font.system(size: 11, weight: .semibold)
}

public extension View {
    /// Section-header style label: tiny uppercase tertiary text used above
    /// groups of metrics in the popover.
    func prusaSectionHeader() -> some View {
        font(.prusaSectionHeader)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.textTertiary)
    }
}

private struct BrandAccentKey: EnvironmentKey {
    static let defaultValue: Theme.Accent = .orange
}

private struct BrandCustomHexKey: EnvironmentKey {
    static let defaultValue: String = ""
}

public extension EnvironmentValues {
    /// The user-selected brand accent used to resolve `Theme.Palette.brand` /
    /// `.brandMuted`. Top-level containers inject the current value from
    /// `AppModel.accent`; nested components read it from the environment.
    var brandAccent: Theme.Accent {
        get { self[BrandAccentKey.self] }
        set { self[BrandAccentKey.self] = newValue }
    }

    /// Hex string (`#RRGGBB`) for the custom accent slot. Only consulted by
    /// `Theme.Palette.brand(_:customHex:)` when `brandAccent == .custom`.
    /// Top-level containers inject the current value from
    /// `AppModel.customAccentHex`.
    var brandCustomHex: String {
        get { self[BrandCustomHexKey.self] }
        set { self[BrandCustomHexKey.self] = newValue }
    }
}

public extension Color {
    /// Parses a `#RRGGBB` or `RRGGBB` sRGB hex string. Returns nil for
    /// malformed input so callers can fall back without crashing.
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    /// Encodes a SwiftUI `Color` as `#RRGGBB`, resolving against sRGB. Falls
    /// back to the input default on platforms or color spaces that cannot be
    /// converted (e.g. dynamic colors without a concrete sample).
    func toHex(default fallback: String = "#000000") -> String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let red = Int((nsColor.redComponent * 255).rounded())
        let green = Int((nsColor.greenComponent * 255).rounded())
        let blue = Int((nsColor.blueComponent * 255).rounded())
        guard (0 ... 255).contains(red), (0 ... 255).contains(green), (0 ... 255).contains(blue) else {
            return fallback
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
