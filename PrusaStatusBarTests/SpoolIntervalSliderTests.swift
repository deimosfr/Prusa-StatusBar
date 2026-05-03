@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `polling` Requirement: Refresh interval is set with a spool-wheel slider.
///   These tests pin the logarithmic mapping that drives the slider so a
///   regression in the math surfaces without needing a SwiftUI host.
struct SpoolIntervalSliderTests {
    private let connectedBounds = UserPreferences.refreshIntervalMin
        ... UserPreferences.refreshIntervalMax
    private let disconnectedBounds = UserPreferences.disconnectedRefreshIntervalMin
        ... UserPreferences.disconnectedRefreshIntervalMax

    @Test
    func progressZeroMapsToLowerBound_connected() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        #expect(mapping.seconds(forProgress: 0.0) == connectedBounds.lowerBound)
    }

    @Test
    func progressOneMapsToUpperBound_connected() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        #expect(mapping.seconds(forProgress: 1.0) == connectedBounds.upperBound)
    }

    @Test
    func progressZeroMapsToLowerBound_disconnected() {
        let mapping = LogIntervalMapping(bounds: disconnectedBounds)
        #expect(mapping.seconds(forProgress: 0.0) == disconnectedBounds.lowerBound)
    }

    @Test
    func progressOneMapsToUpperBound_disconnected() {
        let mapping = LogIntervalMapping(bounds: disconnectedBounds)
        #expect(mapping.seconds(forProgress: 1.0) == disconnectedBounds.upperBound)
    }

    @Test
    func negativeProgressClampsToLowerBound() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        #expect(mapping.seconds(forProgress: -0.5) == connectedBounds.lowerBound)
        #expect(mapping.seconds(forProgress: -1.0) == connectedBounds.lowerBound)
    }

    @Test
    func progressAboveOneClampsToUpperBound() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        #expect(mapping.seconds(forProgress: 1.5) == connectedBounds.upperBound)
        #expect(mapping.seconds(forProgress: 9.0) == connectedBounds.upperBound)
    }

    @Test
    func progressForSecondsClampsBelowLowerBound() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        #expect(mapping.progress(forSeconds: connectedBounds.lowerBound - 5) == 0.0)
    }

    @Test
    func progressForSecondsClampsAboveUpperBound() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        #expect(mapping.progress(forSeconds: connectedBounds.upperBound + 5000) == 1.0)
    }

    @Test
    func mappingIsMonotonicNonDecreasing_connected() {
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        var previous = mapping.seconds(forProgress: 0.0)
        for step in 1 ... 100 {
            let current = mapping.seconds(forProgress: Double(step) / 100.0)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test
    func mappingIsMonotonicNonDecreasing_disconnected() {
        let mapping = LogIntervalMapping(bounds: disconnectedBounds)
        var previous = mapping.seconds(forProgress: 0.0)
        for step in 1 ... 100 {
            let current = mapping.seconds(forProgress: Double(step) / 100.0)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test
    func roundTripStaysInsideOneBucket_connected() {
        // Round-tripping a value through `progress -> seconds` should land us
        // back on the same integer (rounding is the only lossy step).
        let mapping = LogIntervalMapping(bounds: connectedBounds)
        for value in connectedBounds.lowerBound ... connectedBounds.upperBound {
            let progress = mapping.progress(forSeconds: value)
            let restored = mapping.seconds(forProgress: progress)
            #expect(restored == value, "round-trip drift at \(value): got \(restored)")
        }
    }

    @Test
    func roundTripStaysInsideOneBucket_disconnected() {
        let mapping = LogIntervalMapping(bounds: disconnectedBounds)
        for value in disconnectedBounds.lowerBound ... disconnectedBounds.upperBound {
            let progress = mapping.progress(forSeconds: value)
            let restored = mapping.seconds(forProgress: progress)
            #expect(restored == value, "round-trip drift at \(value): got \(restored)")
        }
    }
}
