import Foundation

/// Reconnect backoff for the live camera player. Direct RTSP either connects
/// within a second or two or fails fast, so the schedule is short: a few quick
/// attempts, then a slow steady retry so the tile self-heals if the camera
/// comes back. (The former go2rtc + HLS pipeline needed a ~23 s budget to
/// cover HLS-playlist warm-up; that no longer applies with direct playback.)
///
/// Pure value type so the schedule and the one-shot "budget exhausted" signal
/// are unit-testable without VLCKit.
struct StreamRetryPolicy {
    private let backoffs: [TimeInterval]
    private let slowRetry: TimeInterval
    private(set) var attempt: Int = 0

    init(backoffs: [TimeInterval] = [1, 2, 4, 8], slowRetry: TimeInterval = 10) {
        self.backoffs = backoffs
        self.slowRetry = slowRetry
    }

    mutating func reset() {
        attempt = 0
    }

    /// Delay before the next reconnect attempt. The first time the fast budget
    /// is exhausted, `onBudgetExhausted` fires exactly once (the generic tile
    /// uses it to fall back to still-image polling); every later call returns
    /// the slow steady-retry interval.
    mutating func nextDelay(onBudgetExhausted: () -> Void) -> TimeInterval {
        if attempt < backoffs.count {
            let delay = backoffs[attempt]
            attempt += 1
            return delay
        }
        if attempt == backoffs.count {
            onBudgetExhausted()
            attempt += 1
        }
        return slowRetry
    }
}
