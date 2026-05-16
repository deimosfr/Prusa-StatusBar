import Darwin
import Foundation
import os

/// PGID slot read by the C-level `atexit` fallback. Set to the helper's
/// pid after a successful `setpgid(pid, pid)` so a group kill covers any
/// descendants. Zero when `setpgid` was not attempted or failed.
private nonisolated(unsafe) var goRTCTrackedPGID: pid_t = 0

/// Raw PID of the running helper. Always set regardless of whether
/// `setpgid` succeeded. Used by the atexit fallback as a direct-kill
/// backstop for sandboxed runs where `setpgid` returns EPERM.
private nonisolated(unsafe) var goRTCTrackedPID: pid_t = 0

/// `atexit` handler. Touches only the C globals above so it is safe to
/// call from any termination path, including ones that bypass Swift runtime
/// teardown. Tries a process-group kill first (covers descendants when
/// `setpgid` succeeded), then falls back to a direct-PID kill so the
/// helper dies even when the App Sandbox blocked `setpgid`.
@_cdecl("prusaStatusBarGoRTCAtexit")
func prusaStatusBarGoRTCAtexit() {
    let pgid = goRTCTrackedPGID
    if pgid > 0 {
        _ = Darwin.kill(-pgid, SIGKILL)
    }
    let pid = goRTCTrackedPID
    if pid > 0 {
        _ = Darwin.kill(pid, SIGKILL)
    }
}

@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer, _ buffersize: UInt32) -> Int32

private let procPidpathInfoMaxsize: Int = 4 * 1024

/// Spawns a bundled `go2rtc` helper and exposes an HLS endpoint that
/// AVPlayer can consume. go2rtc handles the actual RTSP negotiation, which
/// avoids the SDP-parse bug in libvlc 3.x's pinned live555 client.
///
/// Lifetime: the helper is started lazily the first time a CameraTile
/// appears with an RTSP URL and torn down when the popover closes or the
/// app terminates. Each (re)start writes a fresh config file under the
/// app's container, then launches go2rtc with `-c <config>`.
@MainActor
final class GoRTCService {
    /// Injection seams used by tests to swap the helper binary path, the
    /// pid-file location, the port probe target, and the path-match rule.
    struct Dependencies {
        var helperURL: @Sendable () -> URL?
        var helperArguments: @Sendable (_ configURL: URL) -> [String]
        var pidFileURL: URL
        var configFileURL: URL
        var port: UInt16
        var helperPathMatches: @Sendable (_ resolvedPath: String) -> Bool

        static let live: Dependencies = {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("go2rtc", isDirectory: true)
            return Dependencies(
                helperURL: { Bundle.main.url(forResource: "go2rtc", withExtension: nil) },
                helperArguments: { configURL in ["-c", configURL.path] },
                pidFileURL: dir.appendingPathComponent("go2rtc.pid"),
                configFileURL: dir.appendingPathComponent("go2rtc.yaml"),
                port: 1984,
                helperPathMatches: { resolved in
                    guard let helper = Bundle.main.url(forResource: "go2rtc", withExtension: nil) else {
                        return false
                    }
                    let helperResolved = (try? helper.resourceValues(forKeys: [.canonicalPathKey])
                        .canonicalPath) ?? helper.path
                    return resolved == helperResolved || resolved == helper.path
                }
            )
        }()
    }

    static let shared = GoRTCService(dependencies: .live)

    private let logger = Logger(subsystem: "com.deimosfr.prusastatusbar", category: "go2rtc")
    /// Loopback host the helper binds to. Internal so the same-target
    /// snapshot extension (`GoRTCService+Snapshot.swift`) can build URLs.
    let host = "127.0.0.1"
    /// Internal so the snapshot extension reads the helper port.
    var dependenciesView: Dependencies {
        dependencies
    }

    private var dependencies: Dependencies
    private var process: Process?
    /// True when the helper subprocess is running. Internal so the
    /// snapshot extension can decide whether to keep it after a grab.
    var isHelperRunning: Bool {
        process?.isRunning == true
    }

    /// Snapshot of the last YAML config keyed by `streams:` slot. Used to
    /// short-circuit a restart when nothing actually changed.
    private var currentStreams: [String: String] = [:]

    /// go2rtc `streams:` slot used by the Buddy camera tile. Stable so
    /// existing AVPlayer URLs keep working.
    static let snapshotBuddyStreamName = "camera"
    /// go2rtc `streams:` slot used by the optional Generic camera tile.
    /// Distinct from Buddy so the helper can serve both at once.
    static let snapshotGenericStreamName = "camera_generic"

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Idempotent: returns the HLS URL for the given RTSP source. If the
    /// helper is already running for the same RTSP URL, no work is done.
    /// Otherwise the helper is restarted with the new config.
    ///
    /// go2rtc defaults to UDP transport for RTSP. Many cameras (and some
    /// routers) block UDP RTSP or only support TCP. Forcing TCP via the
    /// go2rtc URL fragment makes the Buddy camera work in the same
    /// conditions where VLC (which defaults to TCP) succeeds.
    func hlsURL(forRTSP rtsp: String) -> URL? {
        upsertStream(name: Self.snapshotBuddyStreamName, source: withTCPTransport(rtsp))
    }

    /// Generic-camera variant: accepts any source go2rtc can transmux
    /// (`rtsp://`, `rtsps://`, `http://` for MJPEG, `https://` for MJPEG).
    /// Idempotent against `currentStreams` so flipping back to a Buddy-only
    /// state does not restart the helper.
    func hlsURL(forGenericStream source: String) -> URL? {
        upsertStream(name: Self.snapshotGenericStreamName, source: source)
    }

    /// Removes the generic stream from the helper config. Used by the
    /// dropdown when the user disables the second camera so the helper
    /// stops pulling that source. Returns immediately if nothing to remove.
    func removeGenericStream() {
        guard currentStreams[Self.snapshotGenericStreamName] != nil else { return }
        var streams = currentStreams
        streams[Self.snapshotGenericStreamName] = nil
        applyStreams(streams)
    }

    /// Internal so the snapshot extension (`GoRTCService+Snapshot.swift`)
    /// can register a stream slot before calling `/api/frame.jpeg`.
    @discardableResult
    func upsertStream(name: String, source: String) -> URL? {
        guard dependencies.helperURL() != nil else {
            logger.error("go2rtc binary not found in app bundle")
            return nil
        }
        var streams = currentStreams
        streams[name] = source
        applyStreams(streams)
        return helperURL(forStream: name)
    }

    private func applyStreams(_ streams: [String: String]) {
        guard let helper = dependencies.helperURL() else { return }
        let needsRestart = process?.isRunning != true || streams != currentStreams
        guard needsRestart else { return }
        killOrphanIfNeeded()
        stop()
        do {
            try start(helper: helper, streams: streams)
            currentStreams = streams
        } catch {
            logger.error("Failed to launch go2rtc: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func helperURL(forStream name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(dependencies.port)
        components.path = "/api/stream.m3u8"
        components.queryItems = [URLQueryItem(name: "src", value: name)]
        return components.url
    }

    func stop() {
        guard let proc = process else {
            currentStreams = [:]
            goRTCTrackedPGID = 0
            goRTCTrackedPID = 0
            removePIDFile()
            return
        }
        process = nil
        currentStreams = [:]
        let pgid = goRTCTrackedPGID
        goRTCTrackedPGID = 0
        goRTCTrackedPID = 0

        guard proc.isRunning else {
            removePIDFile()
            return
        }

        proc.terminate()
        // SIGTERM is async. Defer escalation off the main thread instead of
        // spinning, so callers (popoverDidClose) return immediately. Probe
        // liveness via `kill(pid, 0)` so we do not need to capture the
        // non-Sendable `Process`.
        // The PID file is intentionally left in place here so that
        // killOrphanIfNeeded() can find and kill this process on the next
        // applyStreams call (fast reopen race). reapStaleHelper() handles
        // cleanup on the next app launch if needed.
        let pid = proc.processIdentifier
        let escalationLogger = logger
        Task.detached {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard Darwin.kill(pid, 0) == 0 else { return }
            escalationLogger.warning(
                "go2rtc did not exit on SIGTERM, escalating to SIGKILL on pgid \(pgid, privacy: .public)"
            )
            if pgid > 0 {
                _ = Darwin.kill(-pgid, SIGKILL)
            } else {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }

    /// Called by `AppDelegate.applicationDidFinishLaunching` before any UI
    /// is wired up. If a previous run left an orphaned helper, kill it so
    /// port 1984 is free for the new launch.
    func reapStaleHelper() {
        let pidURL = dependencies.pidFileURL
        guard let data = try? Data(contentsOf: pidURL),
              let text = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = pid_t(text), pid > 1
        else {
            try? FileManager.default.removeItem(at: pidURL)
            return
        }
        // Target must still be a go2rtc process owned by this user. Recycled
        // pids are common, so without this check the reaper would happily
        // SIGKILL whatever process happens to inherit the recycled id.
        if pidLooksLikeHelper(pid) {
            logger.info("Reaping orphan go2rtc pid=\(pid, privacy: .public)")
            _ = Darwin.kill(pid, SIGKILL)
            // Wait briefly for the kernel to tear it down. waitpid is not
            // available since the process is not our child anymore.
            let deadline = Date().addingTimeInterval(0.5)
            while isProcessAlive(pid), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if isProcessAlive(pid) {
                logger.warning("Orphan go2rtc pid=\(pid, privacy: .public) still alive after SIGKILL")
            }
        } else {
            logger.info("Stale pid file points at non-helper process, ignoring")
        }
        try? FileManager.default.removeItem(at: pidURL)

        if isPortBound(dependencies.port) {
            let port = dependencies.port
            logger.fault("Port \(port, privacy: .public) still bound after reap; camera launch may fail")
        }
    }

    private func start(helper: URL, streams: [String: String]) throws {
        let configURL = try writeConfig(streams: streams)
        let proc = Process()
        proc.executableURL = helper
        proc.arguments = dependencies.helperArguments(configURL)
        // Drop stdout/stderr to /dev/null so the helper does not pollute the
        // app's stdout. Switch to a pipe + Logger if remote diagnostics are
        // ever needed.
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        process = proc

        let pid = proc.processIdentifier
        // Put the helper in its own process group so a single
        // kill(-pgid, SIGKILL) downstream covers any descendants. Calling
        // setpgid from the parent right after run() is race-safe, the child
        // is already fork-execed.
        if setpgid(pid, pid) == 0 {
            goRTCTrackedPGID = pid
        } else {
            let err = errno
            logger.warning("setpgid failed pid=\(pid, privacy: .public) errno=\(err, privacy: .public)")
        }
        goRTCTrackedPID = pid
        writePIDFile(pid: pid)
        logger.info("go2rtc launched, pid=\(pid, privacy: .public)")
    }

    private func writeConfig(streams: [String: String]) throws -> URL {
        let configURL = dependencies.configFileURL
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Stable ordering keeps a config diff visually readable in the
        // logs and avoids spurious restarts when the dictionary insertion
        // order shuffles between Buddy + Generic toggles.
        let sortedNames = streams.keys.sorted()
        var streamLines = ""
        for name in sortedNames {
            // swiftlint:disable:next force_unwrapping
            let source = streams[name]!
            streamLines += "  \(name): \(source)\n"
        }
        // YAML keeps things minimal: bind a localhost API only, route each
        // configured source under its slot name, and keep the helper quiet.
        let yaml = """
        api:
          listen: \(host):\(dependencies.port)
        rtsp:
          listen: ""
        webrtc:
          listen: ""
        srtp:
          listen: ""
        log:
          level: warn
        streams:
        \(streamLines)
        """
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    }

    private func writePIDFile(pid: pid_t) {
        let url = dependencies.pidFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "\(pid)".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("Failed to write pid file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removePIDFile() {
        try? FileManager.default.removeItem(at: dependencies.pidFileURL)
    }

    private func pidLooksLikeHelper(_ pid: pid_t) -> Bool {
        var buffer = [UInt8](repeating: 0, count: procPidpathInfoMaxsize)
        let len = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return proc_pidpath(pid, base, UInt32(raw.count))
        }
        guard len > 0 else { return false }
        guard let path = String(bytes: buffer.prefix(Int(len)), encoding: .utf8) else {
            return false
        }
        return dependencies.helperPathMatches(path)
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        // kill(pid, 0) returns 0 if the process exists and we may signal it,
        // -1 with ESRCH when it does not. EPERM means it exists but we
        // cannot signal it; treat as alive.
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    /// Public hook for `AppDelegate` to register the C-level atexit handler
    /// once at startup. Using a wrapper keeps the C function pointer detail
    /// inside this file.
    static func registerAtexitFallback() {
        atexit(prusaStatusBarGoRTCAtexit)
    }
}

/// Process-introspection helpers carved out of the main type to keep
/// `GoRTCService`'s body under the lint budget. Same-file extension so
/// `private` access stays intact.
extension GoRTCService {
    /// Appends `#transport=tcp` to an RTSP URL for go2rtc. If a fragment
    /// already exists the parameter is appended with `&` so existing
    /// go2rtc options are preserved.
    func withTCPTransport(_ rtsp: String) -> String {
        guard rtsp.lowercased().hasPrefix("rtsp") else { return rtsp }
        guard let hashIndex = rtsp.firstIndex(of: "#") else {
            return "\(rtsp)#transport=tcp"
        }
        let fragment = String(rtsp[rtsp.index(after: hashIndex)...])
        let hasTransport = fragment.split(separator: "&").contains {
            $0.split(separator: "=", maxSplits: 1).first.map(String.init) == "transport"
        }
        return hasTransport ? rtsp : "\(rtsp)&transport=tcp"
    }

    /// Reads the PID file written by the previous app session and sends
    /// SIGKILL to the recorded process if it is still alive and the path
    /// of that process matches the bundled helper binary. This prevents an
    /// orphaned go2rtc (left behind by a crash or force-quit, where the
    /// atexit SIGKILL could not reach it because `setpgid` is blocked by
    /// the App Sandbox) from holding port \(dependencies.port) and blocking
    /// a fresh start.
    func killOrphanIfNeeded() {
        guard
            let raw = try? String(contentsOf: dependencies.pidFileURL, encoding: .utf8),
            let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            pid != process?.processIdentifier
        else { return }
        guard isProcessAlive(pid) else {
            removePIDFile()
            return
        }
        guard pidLooksLikeHelper(pid) else {
            removePIDFile()
            return
        }
        logger.warning("killing orphaned go2rtc pid=\(pid, privacy: .public)")
        Darwin.kill(pid, SIGKILL)
        // Wait for the process to die so port 1984 is free before start().
        let deadline = Date().addingTimeInterval(0.3)
        while isProcessAlive(pid), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        removePIDFile()
    }

    func isPortBound(_ port: UInt16) -> Bool {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { Darwin.close(socketFD) }

        let flags = fcntl(socketFD, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockptr in
                Darwin.connect(socketFD, sockptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 { return true }
        if errno != EINPROGRESS { return false }

        var pollSet = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
        let polled = poll(&pollSet, 1, 100)
        guard polled > 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        if getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &soError, &len) != 0 {
            return false
        }
        return soError == 0
    }
}
