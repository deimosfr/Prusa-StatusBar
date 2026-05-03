import Foundation
import SwiftUI

/// "Test camera" button logic for `GenericCameraSection`. Carved out of
/// the main file to keep the section's struct body under the SwiftLint
/// `type_body_length` budget. Same module so `@MainActor` access to the
/// section's `@State` is preserved.
extension GenericCameraSection {
    @MainActor
    func runStreamTest() async {
        isStreamTesting = true
        streamTestResult = nil
        defer { isStreamTesting = false }

        let trimmed = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme != nil else {
            streamTestResult = .failure(L10n.t("printer.generic_camera.error.invalid_url"))
            return
        }
        let snapshot = currentConfigSnapshot()
        let scheme = parsed.scheme?.lowercased()
        if scheme == "rtsp" || scheme == "rtsps" {
            streamTestResult = await testRTSP(originalURL: parsed)
        } else {
            streamTestResult = await testHTTPReachability(url: parsed, config: snapshot)
        }
    }

    @MainActor
    func runStillTest() async {
        isStillTesting = true
        stillTestResult = nil
        defer { isStillTesting = false }

        let trimmed = stillImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            stillTestResult = .failure(L10n.t("printer.generic_camera.error.invalid_url"))
            return
        }
        stillTestResult = await testHTTPReachability(url: parsed, config: currentConfigSnapshot())
    }

    private func currentConfigSnapshot() -> GenericCameraConfig {
        GenericCameraConfig(
            enabled: true,
            streamURL: streamURL,
            stillImageURL: stillImageURL,
            rtspTransport: rtspTransport,
            authMode: authMode,
            username: username,
            password: password,
            framerate: framerate,
            verifySSL: verifySSL,
            contentType: contentType
        )
    }

    @MainActor
    private func testRTSP(originalURL: URL) async -> PrinterTestResult {
        let host = originalURL.host ?? ""
        let port = originalURL.port.flatMap { UInt16(exactly: $0) } ?? 554
        let path = originalURL.path.isEmpty ? "/" : originalURL.path
        let result = await probe.describe(host: host, port: port, path: path, timeout: 4)
        switch result {
        case let .success(info):
            let label = info.sessionDescription?
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
                ?? L10n.t("printer.camera.reachable")
            return .success(label)
        case let .failure(error):
            return .failure(genericCameraRTSPProbeMessage(error))
        }
    }

    @MainActor
    private func testHTTPReachability(url: URL, config: GenericCameraConfig) async -> PrinterTestResult {
        let delegate = GenericCameraTestSessionDelegate(
            authMode: config.authMode,
            username: config.username,
            password: config.password,
            verifySSL: config.verifySSL
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.contentType, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) {
                return .success(L10n.t("printer.camera.reachable"))
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return .failure(String(format: L10n.t("printer.generic_camera.error.http_status"), code))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

@MainActor
private func genericCameraRTSPProbeMessage(_ error: RTSPProbeError) -> String {
    switch error {
    case .timeout: return L10n.t("error.rtsp.timeout")
    case let .connectionFailed(reason): return reason
    case .invalidHost: return L10n.t("error.rtsp.invalid_host")
    case .malformedResponse: return L10n.t("error.rtsp.malformed")
    case let .status(code, reason):
        let reasonText = reason.trimmingCharacters(in: .whitespaces)
        if reasonText.isEmpty {
            return String(format: L10n.t("error.rtsp.status"), code)
        }
        return String(format: L10n.t("error.rtsp.status_with_reason"), code, reasonText)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Composite of the two delegate roles the test session must adopt.
typealias TestSessionDelegateProtocols = NSObject & URLSessionDelegate & URLSessionTaskDelegate

/// Minimal delegate driving the section's "Test" button. Mirrors the
/// `GenericCameraStillFetcher` delegate (basic/digest auth + verify-SSL
/// bypass) without having to spin up a full fetcher loop.
final class GenericCameraTestSessionDelegate: TestSessionDelegateProtocols, @unchecked Sendable {
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
        handleHTTPAuth(method: method, challenge: challenge, completionHandler: completionHandler)
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
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
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
        guard method == want, !username.isEmpty, challenge.previousFailureCount == 0 else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(user: username, password: password, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}
