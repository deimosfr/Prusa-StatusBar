import Darwin
import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `menu-bar-ui` Requirement: Camera helper survives no quit path
///   - Scenario "Graceful quit terminates the helper" (via `stop()`)
/// - `menu-bar-ui` Requirement: Stale helper is reaped on launch
///   - Scenarios "Pid file points at running orphan",
///     "Pid file points at unrelated process", "Pid file absent"
@MainActor
struct GoRTCServiceLifecycleTests {
    @Test
    func stopTerminatesRunningHelper() {
        let (service, paths) = makeService(matchSleep: true)
        defer { try? FileManager.default.removeItem(at: paths.tmpDir) }

        let url = service.hlsURL(forRTSP: "rtsp://example/test")
        #expect(url != nil)

        // PID file should exist after start.
        #expect(FileManager.default.fileExists(atPath: paths.pidFileURL.path))

        service.stop()

        // PID file is removed on stop.
        #expect(FileManager.default.fileExists(atPath: paths.pidFileURL.path) == false)
        // No pid leak in the C-level slot used by the atexit fallback.
        // (We can only observe indirectly via stop being idempotent.)
        service.stop()
    }

    @Test
    func reapStaleHelperKillsMatchingOrphan() throws {
        let (service, paths) = makeService(matchSleep: true)
        defer { try? FileManager.default.removeItem(at: paths.tmpDir) }

        let pid = try spawnDetachedSleep(seconds: 30)
        try writePIDFile(pid: pid, at: paths.pidFileURL)

        service.reapStaleHelper()

        // Reaper should have unlinked the pid file.
        #expect(FileManager.default.fileExists(atPath: paths.pidFileURL.path) == false)

        // Orphan should be gone (kill(-pid, SIGKILL) targets the pgid we set).
        let deadline = Date().addingTimeInterval(0.5)
        while isProcessAlive(pid), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        #expect(isProcessAlive(pid) == false)
    }

    @Test
    func reapStaleHelperLeavesUnrelatedPidAlone() throws {
        // Path matcher refuses /bin/sleep, simulating a recycled pid pointing
        // at a non-helper process. We expect the reaper to skip the kill.
        let (service, paths) = makeService(matchSleep: false)
        defer { try? FileManager.default.removeItem(at: paths.tmpDir) }

        let pid = try spawnDetachedSleep(seconds: 5)
        defer { _ = Darwin.kill(-pid, SIGKILL) }
        try writePIDFile(pid: pid, at: paths.pidFileURL)

        service.reapStaleHelper()

        // Pid file is still cleaned up.
        #expect(FileManager.default.fileExists(atPath: paths.pidFileURL.path) == false)
        // Process must still be alive: the matcher rejected it.
        #expect(isProcessAlive(pid) == true)
    }

    @Test
    func reapStaleHelperWithNoPIDFileIsNoOp() {
        let (service, paths) = makeService(matchSleep: true)
        defer { try? FileManager.default.removeItem(at: paths.tmpDir) }

        // Sanity: file does not exist yet.
        #expect(FileManager.default.fileExists(atPath: paths.pidFileURL.path) == false)

        service.reapStaleHelper()

        #expect(FileManager.default.fileExists(atPath: paths.pidFileURL.path) == false)
    }

    // MARK: - Helpers

    private struct Paths {
        let tmpDir: URL
        let pidFileURL: URL
        let configFileURL: URL
    }

    private func makeService(matchSleep: Bool) -> (GoRTCService, Paths) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prusa-statusbar-tests-\(UUID().uuidString)", isDirectory: true)
        let pidFileURL = tmpDir.appendingPathComponent("go2rtc.pid")
        let configFileURL = tmpDir.appendingPathComponent("go2rtc.yaml")
        let sleepURL = URL(fileURLWithPath: "/bin/sleep")

        let dependencies = GoRTCService.Dependencies(
            helperURL: { sleepURL },
            // /bin/sleep ignores the YAML config, just give it a long duration.
            helperArguments: { _ in ["120"] },
            pidFileURL: pidFileURL,
            configFileURL: configFileURL,
            port: 49999, // unused under the sleep harness, just don't collide with the live 1984
            helperPathMatches: { matchSleep ? $0 == "/bin/sleep" : false }
        )

        return (GoRTCService(dependencies: dependencies),
                Paths(tmpDir: tmpDir, pidFileURL: pidFileURL, configFileURL: configFileURL))
    }

    private func spawnDetachedSleep(seconds: Int) throws -> pid_t {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["\(seconds)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        let pid = proc.processIdentifier
        // Match production: put the child in its own process group so that
        // kill(-pid, SIGKILL) reaches it.
        if setpgid(pid, pid) != 0 {
            let err = errno
            // Race: child may have already execed and set its own pgid. That
            // is also fine for our test as long as the pgid is `pid`.
            if err != EACCES {
                throw POSIXError(.init(rawValue: err) ?? .EPERM)
            }
        }
        return pid
    }

    private func writePIDFile(pid: pid_t, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "\(pid)".write(to: url, atomically: true, encoding: .utf8)
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
