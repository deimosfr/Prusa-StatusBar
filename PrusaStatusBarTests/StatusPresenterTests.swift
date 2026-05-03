import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Menu-bar item shows icon and short label
/// - `menu-bar-ui` Scenarios about printing/idle/finished/disconnected labels
struct StatusPresenterTests {
    @Test
    func printingShowsPercentAndCompactDuration() {
        let status = PrinterStatus(
            state: .printing,
            progress: 0.62,
            timeRemaining: 9 * 3600 + 32 * 60,
            timePrinting: 0
        )
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .animatedPrinting)
        #expect(presentation.label == "62% 9h32m")
    }

    @Test
    func printingHidesRemainingTimeWhenRequested() {
        let status = PrinterStatus(state: .printing, progress: 0.62, timeRemaining: 1000)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: false,
            showPercentage: true
        )
        #expect(presentation.label == "62%")
    }

    @Test
    func printingHidesPercentageWhenRequested() {
        let status = PrinterStatus(state: .printing, progress: 0.62, timeRemaining: 9 * 3600 + 32 * 60)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: false
        )
        #expect(presentation.label == "9h32m")
    }

    @Test
    func printingWithBothTogglesOffYieldsEmptyLabel() {
        let status = PrinterStatus(state: .printing, progress: 0.62, timeRemaining: 1000)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: false,
            showPercentage: false
        )
        #expect(presentation.label == "")
        #expect(presentation.icon == .animatedPrinting)
    }

    @Test
    func pausedUsesPausedAsset() {
        let status = PrinterStatus(state: .paused, progress: 0.5, timeRemaining: 600)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .asset("IconPaused"))
    }

    @Test
    func idleHasEmptyLabel() {
        let status = PrinterStatus(state: .idle)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.label == "")
        #expect(presentation.icon == .asset("IconIdle"))
    }

    @Test
    func finishedAlwaysShows100() {
        let status = PrinterStatus(state: .finished, progress: 1.0)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.label == "100%")
        #expect(presentation.icon == .asset("IconFinished"))
    }

    @Test
    func finishedOmitsLabelWhenPercentageHidden() {
        let status = PrinterStatus(state: .finished, progress: 1.0)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: false
        )
        #expect(presentation.label == "")
        #expect(presentation.icon == .asset("IconFinished"))
    }

    @Test
    func disconnectedSwitchesIcon() {
        let status = PrinterStatus(state: .printing, progress: 0.5, timeRemaining: 60)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: true,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .asset("IconDisconnected"))
        #expect(presentation.label == "")
    }

    @Test
    func notConfiguredFallsBackToIdleAsset() {
        let presentation = StatusPresenter.present(
            status: nil,
            isDisconnected: false,
            isConfigured: false,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .asset("IconIdle"))
        #expect(presentation.label == "")
    }

    @Test
    func busyUsesBusyAsset() {
        let status = PrinterStatus(state: .busy)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .asset("IconBusy"))
    }

    @Test
    func attentionUsesAttentionAsset() {
        let status = PrinterStatus(state: .attention, progress: 0.4)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .asset("IconAttention"))
    }

    @Test
    func stoppedUsesStoppedAsset() {
        let status = PrinterStatus(state: .stopped)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true
        )
        #expect(presentation.icon == .asset("IconStopped"))
    }

    // MARK: - Compact duration formatter

    @Test
    func formatsSecondsOnlyWhenLessThanAMinute() {
        #expect(StatusPresenter.formatCompactDuration(seconds: 45) == "45s")
        #expect(StatusPresenter.formatCompactDuration(seconds: 0) == "0s")
    }

    @Test
    func formatsMinutesAndHours() {
        #expect(StatusPresenter.formatCompactDuration(seconds: 60) == "1m")
        #expect(StatusPresenter.formatCompactDuration(seconds: 3661) == "1h1m")
        #expect(StatusPresenter.formatCompactDuration(seconds: 86400 + 3600) == "1d1h")
    }

    @Test
    func capsToTwoUnits() {
        // 1d 2h 3m 4s, only the two leading non-zero units.
        let total = 86400 + 2 * 3600 + 3 * 60 + 4
        #expect(StatusPresenter.formatCompactDuration(seconds: total) == "1d2h")
    }

    // MARK: - Animated printing surface

    @Test
    func printingMenuBarIconIsAnimatedPrinting() {
        // Spec: menu-bar `.printing` returns the marker `IconSource` so the
        // controller can drive the bounded burst + settle on
        // `IconPrintingStatic`. The popover side keeps the asset-name path.
        let status = PrinterStatus(state: .printing, progress: 0.1, timeRemaining: 0)
        let presentation = StatusPresenter.present(
            status: status,
            isDisconnected: false,
            isConfigured: true,
            showRemainingTime: false,
            showPercentage: false
        )
        #expect(presentation.icon == .animatedPrinting)
    }

    @Test
    func printingStaticAssetNamePointsAtKeyframe10() {
        // The settled rest pose is keyframe 10 of the burst animation,
        // so the menu bar lands on the same visual the wind-down ends on.
        #expect(StatusPresenter.AssetName.printingStatic == "IconPrinting_10")
    }

    @Test
    func assetNameForPrintingStaysIconPrinting() {
        // The popover's `StatusPill` reads `assetName(for:)` for non-printing
        // states; the `.printing` branch is handled by an animated SwiftUI
        // view, but `assetName(for: .printing)` must still resolve to the
        // canonical asset (used by other surfaces and as a fallback).
        #expect(StatusPresenter.assetName(for: .printing) == "IconPrinting")
    }

    // MARK: - assetName helper (shared with StatusPill)

    @Test
    func assetNameMatchesEachState() {
        #expect(StatusPresenter.assetName(for: .printing) == "IconPrinting")
        #expect(StatusPresenter.assetName(for: .paused) == "IconPaused")
        #expect(StatusPresenter.assetName(for: .finished) == "IconFinished")
        #expect(StatusPresenter.assetName(for: .stopped) == "IconStopped")
        #expect(StatusPresenter.assetName(for: .busy) == "IconBusy")
        #expect(StatusPresenter.assetName(for: .attention) == "IconAttention")
        #expect(StatusPresenter.assetName(for: .error) == "IconAttention")
        #expect(StatusPresenter.assetName(for: .idle) == "IconIdle")
        #expect(StatusPresenter.assetName(for: .ready) == "IconIdle")
    }

    @Test
    func assetNameOverridesForDisconnectedAndUnconfigured() {
        #expect(
            StatusPresenter.assetName(for: .printing, isDisconnected: true) == "IconDisconnected"
        )
        #expect(
            StatusPresenter.assetName(for: .printing, isConfigured: false) == "IconIdle"
        )
        // Unconfigured wins over disconnected.
        #expect(
            StatusPresenter.assetName(
                for: .printing,
                isDisconnected: true,
                isConfigured: false
            ) == "IconIdle"
        )
    }
}

/// Spec coverage:
/// - `menu-bar-ui` Requirement: ETA pill in the job card
struct StatusPresenterEtaPillTests {
    /// Fixed calendar so weekday names and day-diff math are deterministic
    /// across CI hosts. UTC + Gregorian + en_US_POSIX yields stable `EEE`
    /// abbreviations (Sun, Mon, Tue, ...).
    private static func fixedCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    /// Anchors `now` to a known UTC instant so `eta = now + delta` lands on
    /// a predictable calendar day under the fixed calendar above.
    /// 2026-05-10 12:00:00 UTC, a Sunday.
    private static func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_778_414_400)
    }

    @Test
    func etaPillSameDayShowsClockOnly() {
        let cal = Self.fixedCalendar()
        let now = Self.fixedNow()
        let eta = now.addingTimeInterval(2 * 3600)
        #expect(
            StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal)
                == StatusPresenter.formatClockTime(eta)
        )
    }

    @Test
    func etaPillTomorrowPrefixesWeekday() {
        // now = Sun 12:00 UTC, eta = Mon 12:00 UTC.
        let cal = Self.fixedCalendar()
        let now = Self.fixedNow()
        let eta = now.addingTimeInterval(24 * 3600)
        let expected = "Mon \(StatusPresenter.formatClockTime(eta))"
        #expect(StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal) == expected)
    }

    @Test
    func etaPillSixDaysAheadStillUsesWeekday() {
        // now = Sun, eta = Sat (six days later).
        let cal = Self.fixedCalendar()
        let now = Self.fixedNow()
        let eta = now.addingTimeInterval(6 * 24 * 3600)
        let expected = "Sat \(StatusPresenter.formatClockTime(eta))"
        #expect(StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal) == expected)
    }

    @Test
    func etaPillSevenDaysAheadSwitchesToRelative() {
        let cal = Self.fixedCalendar()
        let now = Self.fixedNow()
        let eta = now.addingTimeInterval(7 * 24 * 3600)
        let expected = "+7d \(StatusPresenter.formatClockTime(eta))"
        #expect(StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal) == expected)
    }

    @Test
    func etaPillEightDaysAheadShowsDelta() {
        let cal = Self.fixedCalendar()
        let now = Self.fixedNow()
        let eta = now.addingTimeInterval(8 * 24 * 3600)
        let expected = "+8d \(StatusPresenter.formatClockTime(eta))"
        #expect(StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal) == expected)
    }

    @Test
    func etaPillInThePastFallsBackToClock() {
        // Defensive: if `eta` precedes `now` (clock skew, late tick), the
        // helper SHALL still return the clock-only form rather than a
        // negative day prefix.
        let cal = Self.fixedCalendar()
        let now = Self.fixedNow()
        let eta = now.addingTimeInterval(-3600)
        #expect(
            StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal)
                == StatusPresenter.formatClockTime(eta)
        )
    }

    @Test
    func etaPillAcrossMidnightIsTreatedAsNextDay() {
        // now = 2026-05-10 23:50 UTC (Sunday).
        // eta = 2026-05-11 00:10 UTC (Monday) -- only 20 minutes later, but
        // a calendar-day boundary has been crossed, so the weekday prefix
        // SHALL apply.
        let cal = Self.fixedCalendar()
        let now = Date(timeIntervalSince1970: 1_778_457_000)
        let eta = now.addingTimeInterval(20 * 60)
        let expected = "Mon \(StatusPresenter.formatClockTime(eta))"
        #expect(StatusPresenter.formatEtaPill(eta: eta, now: now, calendar: cal) == expected)
    }
}
