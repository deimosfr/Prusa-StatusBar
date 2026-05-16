import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Temperature Direction Indicator
@MainActor
struct TempCardArrowStateTests {
    private func card(_ current: Double, target: Double) -> TempCard {
        TempCard(heater: .nozzle, temperature: Temperature(current: current, target: target))
    }

    @Test
    func heatingArrow_belowTarget() {
        #expect(card(45, target: 230).arrowState == .heating)
    }

    @Test
    func heatingArrow_justBelowTarget() {
        #expect(card(229, target: 230).arrowState == .heating)
    }

    @Test
    func noArrow_atTarget() {
        #expect(card(230, target: 230).arrowState == .none)
    }

    @Test
    func noArrow_aboveTarget() {
        #expect(card(231, target: 230).arrowState == .none)
    }

    @Test
    func coolingArrow_noTargetHot() {
        #expect(card(80, target: 0).arrowState == .cooling)
    }

    @Test
    func coolingArrow_justAboveThreshold() {
        #expect(card(TempCard.ambientThresholdCelsius + 0.1, target: 0).arrowState == .cooling)
    }

    @Test
    func noArrow_noTargetAtThreshold() {
        #expect(card(TempCard.ambientThresholdCelsius, target: 0).arrowState == .none)
    }

    @Test
    func noArrow_noTargetCold() {
        #expect(card(22, target: 0).arrowState == .none)
    }
}
