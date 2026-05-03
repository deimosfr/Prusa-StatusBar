import Foundation
import SwiftUI

/// Horizontal slider whose thumb is the Prusa filament-spool icon. Maps the
/// editor's `bounds` onto the track via a logarithmic scale (so the bottom
/// half of the track covers the values most users actually pick), and
/// rotates the spool while the user drags so the wheel feels like it's
/// "spending filament" in proportion to drag distance.
///
/// Used in `RefreshIntervalEditor` for both the connected and disconnected
/// refresh-interval rows.
struct SpoolIntervalSlider: View {
    @Binding var seconds: Int
    let bounds: ClosedRange<Int>

    @Environment(\.brandAccent) private var brandAccent
    @Environment(\.brandCustomHex) private var brandCustomHex

    @State private var dragRotation: Double = 0
    @State private var dragStartRotation: Double?
    @State private var isDragging = false

    private static let thumbSize: CGFloat = 28
    private static let trackHeight: CGFloat = 6
    private static let degreesPerPoint: Double = 6
    private static let voiceOverStep: Double = 0.1

    private var mapping: LogIntervalMapping {
        LogIntervalMapping(bounds: bounds)
    }

    var body: some View {
        let accent = Theme.Palette.brand(brandAccent, customHex: brandCustomHex)
        GeometryReader { geo in
            let usable = max(geo.size.width - Self.thumbSize, 1)
            let progress = mapping.progress(forSeconds: seconds)
            let thumbCenterX = Self.thumbSize / 2 + usable * progress

            ZStack {
                Capsule()
                    .fill(Theme.Palette.hairline)
                    .frame(width: geo.size.width, height: Self.trackHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Capsule()
                    .fill(accent)
                    .frame(width: max(thumbCenterX, 0), height: Self.trackHeight)
                    .position(x: max(thumbCenterX, 0) / 2, y: geo.size.height / 2)

                SpoolThumb(
                    fillProgress: progress,
                    bodyRotationDegrees: dragRotation,
                    filamentColor: accent
                )
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                .scaleEffect(isDragging ? 1.06 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
                .position(x: thumbCenterX, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging { isDragging = true }
                        handleDrag(value: value, usableWidth: usable)
                    }
                    .onEnded { _ in
                        dragStartRotation = nil
                        isDragging = false
                    }
            )
        }
        .frame(height: Self.thumbSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("a11y.refresh_interval"))
        .accessibilityValue(RefreshIntervalEditor.formatted(seconds: seconds))
        .accessibilityAdjustableAction { direction in
            adjust(direction: direction)
        }
    }

    private func handleDrag(value: DragGesture.Value, usableWidth: CGFloat) {
        if dragStartRotation == nil {
            dragStartRotation = dragRotation
        }
        let snapshot = dragStartRotation ?? dragRotation
        dragRotation = snapshot + Double(value.translation.width) * Self.degreesPerPoint

        let rawProgress = (value.location.x - Self.thumbSize / 2) / usableWidth
        let newSeconds = mapping.seconds(forProgress: Double(rawProgress))
        if newSeconds != seconds {
            seconds = newSeconds
        }
    }

    private func adjust(direction: AccessibilityAdjustmentDirection) {
        let progress = mapping.progress(forSeconds: seconds)
        let next: Double
        switch direction {
        case .increment: next = min(1.0, progress + Self.voiceOverStep)
        case .decrement: next = max(0.0, progress - Self.voiceOverStep)
        @unknown default: return
        }
        let newSeconds = mapping.seconds(forProgress: next)
        if newSeconds != seconds {
            seconds = newSeconds
        }
    }
}

/// Logarithmic mapping between an integer interval (in seconds) and a
/// `[0, 1]` progress value along the slider track. Pulled out of the view
/// so unit tests can exercise the math without driving a SwiftUI hierarchy.
struct LogIntervalMapping {
    let bounds: ClosedRange<Int>

    private var logLower: Double {
        Foundation.log(Double(bounds.lowerBound))
    }

    private var logUpper: Double {
        Foundation.log(Double(bounds.upperBound))
    }

    func progress(forSeconds value: Int) -> Double {
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        let span = logUpper - logLower
        guard span > 0 else { return 0 }
        return (Foundation.log(Double(clamped)) - logLower) / span
    }

    func seconds(forProgress progress: Double) -> Int {
        let clamped = min(max(progress, 0.0), 1.0)
        let raw = exp(logLower + clamped * (logUpper - logLower)).rounded()
        let intValue = Int(raw)
        return min(max(intValue, bounds.lowerBound), bounds.upperBound)
    }
}

#if DEBUG
    private struct SpoolIntervalSliderPreview: View {
        @State private var connected = 10
        @State private var disconnected = 60

        var body: some View {
            Form {
                Section("Connected") {
                    SpoolIntervalSlider(
                        seconds: $connected,
                        bounds: UserPreferences.refreshIntervalMin ... UserPreferences.refreshIntervalMax
                    )
                }
                Section("Disconnected") {
                    SpoolIntervalSlider(
                        seconds: $disconnected,
                        bounds: UserPreferences.disconnectedRefreshIntervalMin
                            ... UserPreferences.disconnectedRefreshIntervalMax
                    )
                }
            }
            .formStyle(.grouped)
            .frame(width: 480, height: 240)
        }
    }

    #Preview {
        SpoolIntervalSliderPreview()
    }
#endif
