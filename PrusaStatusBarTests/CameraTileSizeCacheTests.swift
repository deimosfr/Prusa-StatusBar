import CoreGraphics
import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage: `menu-bar-ui` Requirement -- Camera tile size stays
/// stable across reopens while online.
@MainActor
struct CameraTileSizeCacheTests {
    @Test
    func commitSeedsCacheForKind() {
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .buddy, height: 193)
        #expect(model.cameraTileHeights[.buddy] == 193)
        #expect(model.cameraTileHeights[.generic] == nil)
    }

    @Test
    func commitIgnoresZeroHeight() {
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .generic, height: 0)
        #expect(model.cameraTileHeights[.generic] == nil)
    }

    @Test
    func commitIsIdempotentForSameValue() {
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .buddy, height: 200)
        CameraTileSizeCache.commit(model: model, kind: .buddy, height: 200)
        #expect(model.cameraTileHeights[.buddy] == 200)
    }

    @Test
    func buddyAndGenericCacheIndependently() {
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .buddy, height: 180)
        CameraTileSizeCache.commit(model: model, kind: .generic, height: 240)
        #expect(model.cameraTileHeights[.buddy] == 180)
        #expect(model.cameraTileHeights[.generic] == 240)
    }

    @Test
    func clearEmptiesEveryEntry() {
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .buddy, height: 180)
        CameraTileSizeCache.commit(model: model, kind: .generic, height: 240)
        model.clearCameraTileHeights()
        #expect(model.cameraTileHeights.isEmpty)
    }

    /// `isDisconnected` only flips true once the printer fails twice in
    /// a row with `.unreachable`. The DropdownView clear-on-offline
    /// effect must not fire on a single transient blip.
    @Test
    func singleTransientFailureLeavesIsDisconnectedFalse() {
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .buddy, height: 180)
        model.lastError = .unreachable
        model.consecutiveFailures = 1
        #expect(model.isDisconnected == false)
        // The cache survives a single transient failure (the
        // DropdownView clear effect only triggers when isDisconnected
        // flips true).
        #expect(model.cameraTileHeights[.buddy] == 180)
    }

    @Test
    func twoConsecutiveUnreachableFailuresFlipIsDisconnected() {
        let model = AppModel()
        model.lastError = .unreachable
        model.consecutiveFailures = 2
        #expect(model.isDisconnected == true)
    }

    @Test
    func popoverToggleDoesNotTouchCacheBySpec() {
        // The cache is in-memory and is intentionally not coupled to
        // the popover lifecycle: closing and reopening the menu while
        // the printer remains online MUST keep the cache intact.
        let model = AppModel()
        CameraTileSizeCache.commit(model: model, kind: .generic, height: 220)
        model.popoverVisible = true
        model.popoverVisible = false
        model.popoverVisible = true
        #expect(model.cameraTileHeights[.generic] == 220)
    }
}
