import SwiftUI

/// Composite spool thumb: spool body image + dynamic filament overlay,
/// with a static 90 degree rotation that aligns the filament tail with the
/// horizontal slider axis. The spool body rotates while the caller drives
/// `bodyRotationDegrees` (matching the spinning behavior of the original
/// animated Prusa loading wheel) while the filament group stays put,
/// exactly the same separation the source SVG makes between its
/// `<g class="filament">` and `<g class="spool">` groups.
///
/// Used by both `SpoolIntervalSlider` (drag-driven rotation) and
/// `ProgressBarSpool` (progress-driven rotation).
struct SpoolThumb: View {
    /// `0` = full spool, `1` = empty spool. Callers map their own
    /// progress signal onto this axis.
    let fillProgress: Double
    /// Spool-body rotation in degrees; cumulative.
    let bodyRotationDegrees: Double
    /// Color used to draw the filament ring. Tracks the user-selected
    /// brand accent so the spool reads orange / legacy-orange / Prusa Pro
    /// green to match the rest of the UI.
    let filamentColor: Color

    var body: some View {
        ZStack {
            Image("SpoolWheel")
                .resizable()
                .interpolation(.high)
                .rotationEffect(.degrees(bodyRotationDegrees))

            FilamentOverlay(fillProgress: fillProgress, color: filamentColor)
        }
        .rotationEffect(.degrees(90))
    }
}

/// Draws the filament ring. Geometry mirrors the `<g class="filament">`
/// group in the source SVG (viewBox `-250 -250 500 500`), with the ring
/// radius and stroke width interpolated between the SVG's "full"
/// (`r=145, sw=130`) and "empty" (`r=80, sw=0`) keyframes.
struct FilamentOverlay: View {
    let fillProgress: Double
    let color: Color

    private static let viewBoxSpan: CGFloat = 500

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width, size.height) / Self.viewBoxSpan
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inv = 1.0 - max(0.0, min(1.0, fillProgress))

            // Filament ring: concentric annulus shrinking toward the hub
            // as `fillProgress` climbs. Stroke width hits zero at empty,
            // which is the correct visual end-state.
            let ringRadius = (80.0 + inv * 65.0) * scale
            let ringWidth = (inv * 130.0) * scale
            if ringWidth > 0.4 {
                var ring = Path()
                ring.addArc(
                    center: center,
                    radius: ringRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360),
                    clockwise: false
                )
                ctx.stroke(ring, with: .color(color), lineWidth: ringWidth)
            }
        }
        .accessibilityHidden(true)
    }
}
