@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `polling` Requirement: Job detail and thumbnail refresh on job
///   identity change
///   - Scenario "Same job across polls"
///   - Scenario "Reprint of the same file gets a fresh thumbnail"
///   - Scenario "New file starts printing"
struct PollingCoordinatorJobIdentityTests {
    @Test
    func bothIdsEqualIsSameJob() {
        let a = PrintJob(displayName: "model.bgcode", id: 42)
        let b = PrintJob(displayName: "model.bgcode", id: 42)
        #expect(PollingCoordinator.isSameJob(lhs: a, rhs: b))
    }

    /// Regression guard for issue #20: a reprint reuses the file name but
    /// gets a new upstream `id`, so the identity check MUST return false so
    /// the thumbnail is refetched.
    @Test
    func differentIdsIsNotSameJobEvenWhenNameMatches() {
        let a = PrintJob(displayName: "model.bgcode", id: 42)
        let b = PrintJob(displayName: "model.bgcode", id: 43)
        #expect(!PollingCoordinator.isSameJob(lhs: a, rhs: b))
    }

    @Test
    func nilIdsFallBackToDisplayNameMatch() {
        let a = PrintJob(displayName: "model.bgcode", id: nil)
        let b = PrintJob(displayName: "model.bgcode", id: nil)
        #expect(PollingCoordinator.isSameJob(lhs: a, rhs: b))
    }

    @Test
    func nilIdsFallBackToDisplayNameMismatch() {
        let a = PrintJob(displayName: "first.bgcode", id: nil)
        let b = PrintJob(displayName: "second.bgcode", id: nil)
        #expect(!PollingCoordinator.isSameJob(lhs: a, rhs: b))
    }

    /// Mixed-nullability `id`s fall back to the `displayName` check so
    /// older PrusaLink firmware (which may omit `id` on one side of a
    /// transition) behaves as it did before the fix.
    @Test
    func mixedIdNullabilityFallsBackToDisplayName() {
        let withID = PrintJob(displayName: "model.bgcode", id: 42)
        let withoutID = PrintJob(displayName: "model.bgcode", id: nil)
        #expect(PollingCoordinator.isSameJob(lhs: withID, rhs: withoutID))

        let withIDOther = PrintJob(displayName: "other.bgcode", id: 42)
        #expect(!PollingCoordinator.isSameJob(lhs: withIDOther, rhs: withoutID))
    }

    @Test
    func bothNilIsSameJob() {
        #expect(PollingCoordinator.isSameJob(lhs: nil, rhs: nil))
    }

    @Test
    func oneNilIsNotSameJob() {
        let a = PrintJob(displayName: "model.bgcode", id: 42)
        #expect(!PollingCoordinator.isSameJob(lhs: a, rhs: nil))
        #expect(!PollingCoordinator.isSameJob(lhs: nil, rhs: a))
    }
}
