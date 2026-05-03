import Foundation
import Network

/// Information returned by a successful RTSP `DESCRIBE` probe. The session
/// description (SDP `s=` line) is surfaced in the UI when present so the
/// user gets concrete feedback about what the camera is exposing; otherwise
/// a generic "Camera reachable" message is shown.
public struct RTSPDescribeInfo: Sendable, Equatable {
    public let sessionDescription: String?
    public let mediaLines: [String]

    public init(sessionDescription: String?, mediaLines: [String]) {
        self.sessionDescription = sessionDescription
        self.mediaLines = mediaLines
    }
}

public enum RTSPProbeError: Error, Equatable, Sendable {
    case timeout
    case connectionFailed(String)
    case invalidHost
    case malformedResponse
    case status(code: Int, reason: String)
}

public protocol RTSPProbing: Sendable {
    func describe(host: String, port: UInt16, path: String, timeout: TimeInterval) async
        -> Result<RTSPDescribeInfo, RTSPProbeError>
}

public extension RTSPProbing {
    func describe(host: String) async -> Result<RTSPDescribeInfo, RTSPProbeError> {
        await describe(host: host, port: 554, path: "/live/", timeout: 4)
    }
}

/// Production probe: opens an `NWConnection` over TCP, sends a single
/// RTSP `DESCRIBE` request, parses the status line, optionally extracts SDP
/// `s=` and `m=` lines on a 200-class response. Bound by `timeout`; any I/O
/// or parsing failure surfaces as an `RTSPProbeError`.
public struct LiveRTSPProbe: RTSPProbing {
    public init() {}

    public func describe(
        host: String,
        port: UInt16 = 554,
        path: String = "/live/",
        timeout: TimeInterval = 4
    ) async -> Result<RTSPDescribeInfo, RTSPProbeError> {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            return .failure(.invalidHost)
        }
        let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .tcp)
        let requestLine = "DESCRIBE rtsp://\(trimmedHost):\(port)\(path) RTSP/1.0\r\n"
        let headers = "CSeq: 1\r\nUser-Agent: PrusaStatusBar/1.0\r\nAccept: application/sdp\r\n\r\n"
        guard let payload = (requestLine + headers).data(using: .ascii) else {
            return .failure(.malformedResponse)
        }
        return await runProbe(connection: connection, payload: payload, timeout: timeout)
    }

    private func runProbe(
        connection: NWConnection,
        payload: Data,
        timeout: TimeInterval
    ) async -> Result<RTSPDescribeInfo, RTSPProbeError> {
        await withCheckedContinuation { continuation in
            let state = ProbeState(continuation: continuation, connection: connection)
            state.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                state.finish(.failure(.timeout))
            }
            connection.stateUpdateHandler = { [payload] newState in
                handleStateChange(newState, connection: connection, payload: payload, state: state)
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

private func handleStateChange(
    _ newState: NWConnection.State,
    connection: NWConnection,
    payload: Data,
    state: ProbeState
) {
    switch newState {
    case .ready:
        sendAndReceive(connection: connection, payload: payload, state: state)
    case let .failed(error):
        state.finish(.failure(.connectionFailed(error.localizedDescription)))
    default:
        break
    }
}

private func sendAndReceive(connection: NWConnection, payload: Data, state: ProbeState) {
    connection.send(content: payload, completion: .contentProcessed { error in
        if let error {
            state.finish(.failure(.connectionFailed(error.localizedDescription)))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, err in
            if let err {
                state.finish(.failure(.connectionFailed(err.localizedDescription)))
                return
            }
            guard let data, !data.isEmpty,
                  let response = String(data: data, encoding: .ascii)
                  ?? String(data: data, encoding: .utf8)
            else {
                state.finish(.failure(.malformedResponse))
                return
            }
            state.finish(parseDescribeResponse(response))
        }
    })
}

/// Stub probe used in unit tests and `PROTOTYPE_MODE` builds. Returns the
/// caller-supplied result without touching the network.
public struct StubRTSPProbe: RTSPProbing {
    private let stubResult: Result<RTSPDescribeInfo, RTSPProbeError>

    public init(stubResult: Result<RTSPDescribeInfo, RTSPProbeError>) {
        self.stubResult = stubResult
    }

    public func describe(
        host _: String, port _: UInt16, path _: String, timeout _: TimeInterval
    ) async -> Result<RTSPDescribeInfo, RTSPProbeError> {
        stubResult
    }
}

private func parseDescribeResponse(_ response: String) -> Result<RTSPDescribeInfo, RTSPProbeError> {
    let lines = response.components(separatedBy: "\r\n")
    guard let statusLine = lines.first else {
        return .failure(.malformedResponse)
    }
    let statusParts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    guard statusParts.count >= 2,
          statusParts[0].hasPrefix("RTSP/"),
          let code = Int(statusParts[1])
    else {
        return .failure(.malformedResponse)
    }
    if !(200 ..< 300).contains(code) {
        let reason = statusParts.count >= 3 ? String(statusParts[2]) : ""
        return .failure(.status(code: code, reason: reason))
    }
    var sessionDescription: String?
    var mediaLines: [String] = []
    for line in lines {
        if line.hasPrefix("s=") {
            sessionDescription = String(line.dropFirst(2))
        } else if line.hasPrefix("m=") {
            mediaLines.append(String(line.dropFirst(2)))
        }
    }
    return .success(RTSPDescribeInfo(sessionDescription: sessionDescription, mediaLines: mediaLines))
}

/// Internal state holder so the connection's `stateUpdateHandler`, the
/// receive callback, and the timeout task all converge on a single resume of
/// the continuation.
private final class ProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFinished = false
    private let continuation: CheckedContinuation<Result<RTSPDescribeInfo, RTSPProbeError>, Never>
    private let connection: NWConnection
    var timeoutTask: Task<Void, Never>?

    init(
        continuation: CheckedContinuation<Result<RTSPDescribeInfo, RTSPProbeError>, Never>,
        connection: NWConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ result: Result<RTSPDescribeInfo, RTSPProbeError>) {
        lock.lock()
        if hasFinished {
            lock.unlock()
            return
        }
        hasFinished = true
        lock.unlock()
        timeoutTask?.cancel()
        connection.cancel()
        continuation.resume(returning: result)
    }
}
