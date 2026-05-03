import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `update-check` Requirement: App compares latest release tag against
///   the running version (parser + comparator)
struct SemanticVersionTests {
    @Test
    func parsesPlainTriple() {
        let version = SemanticVersion("1.2.3")
        #expect(version == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test
    func stripsLeadingV() {
        #expect(SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("V0.1.0") == SemanticVersion(major: 0, minor: 1, patch: 0))
    }

    @Test
    func defaultsMissingMinorAndPatchToZero() {
        #expect(SemanticVersion("2") == SemanticVersion(major: 2, minor: 0, patch: 0))
        #expect(SemanticVersion("2.5") == SemanticVersion(major: 2, minor: 5, patch: 0))
    }

    @Test
    func ignoresPreReleaseAndBuildSuffix() {
        #expect(SemanticVersion("1.2.3-beta.1") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("1.2.3+sha.abc") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("v1.2.3-rc1+build.7") == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test
    func rejectsNonNumericInput() {
        #expect(SemanticVersion("not-a-version") == nil)
        #expect(SemanticVersion("1.x.3") == nil)
        #expect(SemanticVersion("") == nil)
    }

    @Test
    func ordersMajorMinorPatch() throws {
        #expect(try #require(SemanticVersion("1.0.0")) < SemanticVersion("2.0.0")!)
        #expect(try #require(SemanticVersion("1.5.0")) > SemanticVersion("1.4.99")!)
        #expect(try #require(SemanticVersion("1.5.10")) > SemanticVersion("1.5.9")!)
        #expect(SemanticVersion("1.5.0") == SemanticVersion("v1.5.0")!)
    }
}
