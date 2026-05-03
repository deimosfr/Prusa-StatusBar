@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Disconnected icon is user-configurable
///   (default / minimal / emoji style scenarios + empty-emoji fallback)
struct StatusPresenterDisconnectedIconTests {
    @Test
    func disconnectedDefaultStyleUsesAsset() {
        let presentation = StatusPresenter.present(
            status: nil,
            isDisconnected: true,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true,
            disconnectedIconStyle: .default
        )
        #expect(presentation.icon == .asset("IconDisconnected"))
        #expect(presentation.label == "")
    }

    @Test
    func disconnectedMinimalStyleUsesMinimalDot() {
        let presentation = StatusPresenter.present(
            status: nil,
            isDisconnected: true,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true,
            disconnectedIconStyle: .minimal
        )
        #expect(presentation.icon == .minimalDot)
        #expect(presentation.label == "")
    }

    @Test
    func disconnectedNoneStyleUsesEmptyImage() {
        let presentation = StatusPresenter.present(
            status: nil,
            isDisconnected: true,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true,
            disconnectedIconStyle: .none
        )
        #expect(presentation.icon == .empty)
        #expect(presentation.label == "")
    }

    @Test
    func disconnectedEmojiStyleUsesProvidedEmoji() {
        let presentation = StatusPresenter.present(
            status: nil,
            isDisconnected: true,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true,
            disconnectedIconStyle: .emoji,
            disconnectedIconEmoji: "💤"
        )
        #expect(presentation.icon == .emoji("💤"))
        #expect(presentation.label == "")
    }

    @Test
    func disconnectedEmojiStyleFallsBackWhenEmpty() {
        let presentation = StatusPresenter.present(
            status: nil,
            isDisconnected: true,
            isConfigured: true,
            showRemainingTime: true,
            showPercentage: true,
            disconnectedIconStyle: .emoji,
            disconnectedIconEmoji: "   "
        )
        #expect(presentation.icon == .asset("IconDisconnected"))
    }
}
