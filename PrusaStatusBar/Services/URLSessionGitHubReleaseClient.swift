import Foundation

/// Production `GitHubReleaseClient` backed by `URLSession`. Issues an
/// unauthenticated GET against the public Releases API: 60 requests per
/// hour per IP, well above the once-per-day budget the update checker
/// uses.
public final class URLSessionGitHubReleaseClient: GitHubReleaseClient, @unchecked Sendable {
    private let session: URLSession
    private let endpoint: URL
    private let timeout: TimeInterval
    private let decoder = JSONDecoder()

    public init(
        session: URLSession? = nil,
        endpoint: URL = URL(string: "https://api.github.com/repos/deimosfr/Prusa-StatusBar/releases/latest")!,
        timeout: TimeInterval = 10
    ) {
        self.session = session ?? URLSessionGitHubReleaseClient.makeSession()
        self.endpoint = endpoint
        self.timeout = timeout
    }

    public func fetchLatestRelease() async -> Result<GitHubRelease, GitHubReleaseError> {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.decoding("non-HTTP response"))
            }
            guard (200 ... 299).contains(http.statusCode) else {
                return .failure(.httpStatus(http.statusCode))
            }
            do {
                let dto = try decoder.decode(LatestReleaseDTO.self, from: data)
                guard let url = URL(string: dto.html_url) else {
                    return .failure(.decoding("html_url is not a valid URL"))
                }
                return .success(GitHubRelease(tag: dto.tag_name, htmlURL: url))
            } catch {
                return .failure(.decoding(error.localizedDescription))
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .cannotConnectToHost,
                     .timedOut,
                     .networkConnectionLost,
                     .notConnectedToInternet,
                     .cannotFindHost,
                     .dnsLookupFailed:
                    return .failure(.unreachable)
                default:
                    return .failure(.decoding(urlError.localizedDescription))
                }
            }
            return .failure(.decoding(error.localizedDescription))
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }
}

/// Minimal subset of the GitHub Releases API payload the checker needs.
/// Keys match the API exactly so `JSONDecoder` works without a custom
/// `CodingKeys` enum.
private struct LatestReleaseDTO: Decodable {
    // swiftlint:disable identifier_name
    let tag_name: String
    let html_url: String
    // swiftlint:enable identifier_name
}
