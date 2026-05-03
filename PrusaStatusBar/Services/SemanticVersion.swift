import Foundation

/// Minimal `MAJOR.MINOR.PATCH` semantic version with a tolerant parser.
/// Strips a leading `v`, ignores pre-release / build suffixes (`-beta.1`,
/// `+sha.abc`), and treats missing minor/patch as zero. Comparable so the
/// update checker can `latest > running` without dragging in a SemVer
/// dependency.
public struct SemanticVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? trimmed
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, let majorValue = Int(parts[0]) else {
            return nil
        }
        let minorValue = parts.count > 1 ? Int(parts[1]) : 0
        let patchValue = parts.count > 2 ? Int(parts[2]) : 0
        guard let minorValue, let patchValue else { return nil }
        major = majorValue
        minor = minorValue
        patch = patchValue
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
