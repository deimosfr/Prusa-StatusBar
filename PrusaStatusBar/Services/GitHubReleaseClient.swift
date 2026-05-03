import Foundation

/// Protocol the app uses to read the latest published release from GitHub.
/// Production: `URLSessionGitHubReleaseClient`. Prototype mode and tests
/// substitute `StubGitHubReleaseClient`.
public protocol GitHubReleaseClient: Sendable {
    func fetchLatestRelease() async -> Result<GitHubRelease, GitHubReleaseError>
}

/// Subset of the GitHub Releases API payload the update checker needs.
/// `tag` is preserved as received (with any leading `v`), the comparison
/// step strips it via `SemanticVersion.init(_:)`. `htmlURL` is the page the
/// callout opens when the user clicks it.
public struct GitHubRelease: Sendable, Equatable {
    public let tag: String
    public let htmlURL: URL

    public init(tag: String, htmlURL: URL) {
        self.tag = tag
        self.htmlURL = htmlURL
    }
}

public enum GitHubReleaseError: Error, Sendable, Equatable {
    case unreachable
    case httpStatus(Int)
    case decoding(String)
}
