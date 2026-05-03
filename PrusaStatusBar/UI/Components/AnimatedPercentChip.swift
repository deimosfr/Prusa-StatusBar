import SwiftUI

/// Floating percent chip whose displayed integer is driven by an
/// `Animatable` scalar so the digits track whatever spring/curve the host
/// applies via `.animation(_, value:)`. Used by both `ProgressBarSpool`
/// and `ProgressBarPremium` so the chip's number stays synced with the
/// chip's position (and the bar fill) under the same spring response.
struct AnimatedPercentChip: View, @preconcurrency Animatable {
    var value: Double
    let accent: Theme.Accent
    let customHex: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    private var clamped: Double {
        max(0, min(1, value))
    }

    var body: some View {
        Text("\(Int((clamped * 100).rounded()))%")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.Palette.brand(accent, customHex: customHex))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .fixedSize(horizontal: true, vertical: true)
            .shadow(color: Theme.Palette.brand(accent, customHex: customHex).opacity(0.35), radius: 4, y: 1)
            // Publish the chip's measured width so the host bar can clamp
            // its horizontal position against the bar's bounds without
            // hard-coding an estimate (the chip's intrinsic width depends
            // on its rendered digits: "0%" is narrower than "100%").
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AnimatedPercentChipWidthKey.self,
                        value: proxy.size.width
                    )
                }
            )
    }
}

/// PreferenceKey carrying the rendered chip width up to the host bar so
/// the bar can position the chip flush with its leading or trailing edge
/// when the fill is too small (or too large) for the chip to sit centered
/// over the fill edge without clipping.
struct AnimatedPercentChipWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
