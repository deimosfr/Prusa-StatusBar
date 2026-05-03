import SwiftUI

/// Drives a synthetic, looping progress value through one of the two
/// candidate progress-bar styles so the user can see each style in motion
/// while picking. No real printer data is ever shown here.
///
/// The preview drives a trapezoidal wave: hold at 0%, ramp up to 100%,
/// hold at 100%, ramp down to 0%, repeat. Each new cycle bumps the
/// `resetToken` we hand to the underlying bar so the premium style
/// replays its sheen sweep on every loop instead of freezing after the
/// first three cycles (which is what `ProgressBarPremium` does inside the
/// real dropdown to avoid burning CPU after the user has had a chance to
/// read the bar).
struct ProgressBarStylePreview: View {
    let style: ProgressBarStyle

    private static let holdSeconds: TimeInterval = 1.0
    private static let rampSeconds: TimeInterval = 2.0
    private static let cyclePeriod: TimeInterval = (holdSeconds + rampSeconds) * 2

    var body: some View {
        // Cap the preview to 30fps. The outer TimelineView feeds a fresh
        // `value` to the inner bar on every tick; pumping at the display
        // refresh rate (up to 120Hz on ProMotion) compounds with the
        // spring transactions inside the bar and stutters on slower
        // machines. 30fps is visually smooth for a trapezoidal ramp and
        // halves to quarters the per-frame layout work.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let t = elapsed.truncatingRemainder(dividingBy: Self.cyclePeriod)
            let value = trapezoidValue(at: t)
            let token = Int(elapsed / Self.cyclePeriod)

            // Disable spring animations inside the preview: the outer
            // `TimelineView` already supplies a smooth value stream, and
            // re-animating each per-frame value bump with a 1.1s spring
            // stacks transactions until the runloop spins.
            Group {
                switch style {
                case .premium:
                    ProgressBarPremium(value: value, resetToken: token)
                case .spool:
                    ProgressBarSpool(value: value, resetToken: token)
                }
            }
            .transaction { $0.animation = nil }
        }
        .accessibilityHidden(true)
    }

    /// Trapezoidal envelope:
    ///   [0, hold)              -> 0
    ///   [hold, hold+ramp)      -> 0 → 1
    ///   [hold+ramp, 2h+ramp)   -> 1
    ///   [2h+ramp, 2h+2ramp)    -> 1 → 0
    private func trapezoidValue(at t: TimeInterval) -> Double {
        let h = Self.holdSeconds
        let r = Self.rampSeconds
        if t < h {
            return 0
        } else if t < h + r {
            return (t - h) / r
        } else if t < 2 * h + r {
            return 1
        } else {
            return 1 - (t - (2 * h + r)) / r
        }
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 24) {
            ProgressBarStylePreview(style: .premium)
            ProgressBarStylePreview(style: .spool)
        }
        .padding()
        .frame(width: 320)
    }
#endif
