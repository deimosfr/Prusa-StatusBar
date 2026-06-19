@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Dropdown embeds Generic Camera tile beneath
///   Buddy tile -- Scenario "Stream fails, falls back to still" (the reconnect
///   budget exhausts once, which drives the still-image fallback).
///
/// The reconnect schedule replaces the former AVPlayer/go2rtc ~23 s warm-up
/// budget with a short direct-RTSP schedule.
struct StreamRetryPolicyTests {
    @Test func fastScheduleThenExhaustedOnceThenSlowSteady() {
        var policy = StreamRetryPolicy(backoffs: [1, 2, 4, 8], slowRetry: 10)
        var exhausted = 0
        let onExhausted = { exhausted += 1 }

        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 1)
        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 2)
        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 4)
        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 8)
        #expect(exhausted == 0)

        // Budget exhausted: callback fires exactly once, then slow steady retry.
        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 10)
        #expect(exhausted == 1)
        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 10)
        #expect(policy.nextDelay(onBudgetExhausted: onExhausted) == 10)
        #expect(exhausted == 1)
    }

    @Test func resetReturnsToTheStartOfTheSchedule() {
        var policy = StreamRetryPolicy(backoffs: [1, 2], slowRetry: 10)
        _ = policy.nextDelay(onBudgetExhausted: {})
        _ = policy.nextDelay(onBudgetExhausted: {})
        policy.reset()
        #expect(policy.attempt == 0)
        #expect(policy.nextDelay(onBudgetExhausted: {}) == 1)
    }
}
