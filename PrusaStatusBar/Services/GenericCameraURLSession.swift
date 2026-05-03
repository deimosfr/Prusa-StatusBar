import Foundation

/// Builds a `URLSession` configured for generic-camera HTTP calls: applies
/// the user's basic/digest credentials via `URLAuthenticationChallenge` and
/// optionally accepts self-signed TLS certificates when verify-SSL is OFF.
///
/// Shared by `GenericCameraStillFetcher` (periodic still polling) and the
/// generic-camera snapshot provider (single notification frame). The session
/// is `.ephemeral` so credentials and cookies do not bleed across tile and
/// snapshot calls.
enum GenericCameraURLSession {
    static func make(for config: GenericCameraConfig) -> URLSession {
        let delegate = GenericCameraURLSessionDelegate(
            authMode: config.authMode,
            username: config.username,
            password: config.password,
            verifySSL: config.verifySSL
        )
        return URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}

/// `URLSessionDelegate` that serves the configured credentials to basic and
/// digest challenges and optionally accepts self-signed certificates. The
/// trust bypass is scoped to the session it is attached to; no other app
/// traffic is affected.
final class GenericCameraURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let authMode: GenericCameraAuthMode
    private let username: String
    private let password: String
    private let verifySSL: Bool

    init(authMode: GenericCameraAuthMode, username: String, password: String, verifySSL: Bool) {
        self.authMode = authMode
        self.username = username
        self.password = password
        self.verifySSL = verifySSL
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust {
            handleServerTrust(challenge: challenge, completionHandler: completionHandler)
            return
        }
        if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
            handleHTTPAuth(method: method, challenge: challenge, completionHandler: completionHandler)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    private func handleServerTrust(
        challenge: URLAuthenticationChallenge,
        completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if verifySSL {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func handleHTTPAuth(
        method: String,
        challenge: URLAuthenticationChallenge,
        completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let want: String
        switch authMode {
        case .basic: want = NSURLAuthenticationMethodHTTPBasic
        case .digest: want = NSURLAuthenticationMethodHTTPDigest
        case .none:
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard method == want, !username.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Cancel after the first failed attempt so a wrong password does
        // not loop forever against the server's challenge.
        guard challenge.previousFailureCount == 0 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let credential = URLCredential(user: username, password: password, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}
