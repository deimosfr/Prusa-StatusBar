import Foundation

/// Deterministic `GitHubReleaseClient` used by `PROTOTYPE_MODE` builds and
/// tests. Alternates between a release whose tag is one minor version
/// above the configured running version and a release whose tag matches
/// the running version, so the FooterBar callout can be reviewed without
/// touching the network.
public actor StubGitHubReleaseClient: GitHubReleaseClient {
    private let runningVersion: SemanticVersion
    private let htmlURL: URL
    private var stepCount: Int = 0

    public init(
        runningVersion: SemanticVersion = SemanticVersion(major: 0, minor: 1, patch: 0),
        htmlURL: URL = URL(string: "https://github.com/deimosfr/Prusa-StatusBar/releases/latest")!
    ) {
        self.runningVersion = runningVersion
        self.htmlURL = htmlURL
    }

    public func fetchLatestRelease() async -> Result<GitHubRelease, GitHubReleaseError> {
        stepCount += 1
        let useNewer = stepCount % 2 == 1
        let tag = if useNewer {
            "v\(runningVersion.major).\(runningVersion.minor + 1).0"
        } else {
            "v\(runningVersion.major).\(runningVersion.minor).\(runningVersion.patch)"
        }
        return .success(GitHubRelease(tag: tag, htmlURL: htmlURL))
    }
}
