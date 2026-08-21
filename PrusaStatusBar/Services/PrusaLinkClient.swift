import Foundation

/// Protocol the app uses to talk to a PrusaLink printer. The production
/// implementation is `URLSessionPrusaLinkClient`; tests and the prototype
/// configuration substitute deterministic fakes.
public protocol PrusaLinkClient: Sendable {
    func fetchStatus() async -> Result<PrinterStatus, PrusaLinkError>
    func fetchJob() async -> Result<PrintJob?, PrusaLinkError>
    func fetchThumbnail(at path: String) async -> Result<Data, PrusaLinkError>
    func fetchInfo() async -> Result<PrinterInfo, PrusaLinkError>
    /// Collects sanitized raw API responses for a support report. Requires an
    /// active or paused print so the current job can be inspected.
    func fetchDiagnosticSnapshot() async -> Result<PrinterDiagnosticSnapshot, PrinterDiagnosticsError>
    /// Reads the OctoPrint-compatible `/api/printer` endpoint for the
    /// `telemetry.material` field. PrusaLink's own `/api/v1/status` does not
    /// surface the loaded filament material on most firmware (MK3.5, MK4,
    /// MK4S, Core One), so this is the only reliable source. Callers should
    /// gate this on the `showFilamentType` toggle to avoid the extra request
    /// when the user does not want the row.
    func fetchLegacyMaterial() async -> Result<String?, PrusaLinkError>
    func resumeJob(id: Int) async -> Result<Void, PrusaLinkError>
    func pauseJob(id: Int) async -> Result<Void, PrusaLinkError>
    func stopJob(id: Int) async -> Result<Void, PrusaLinkError>
}

/// Carries the per-call configuration for a `PrusaLinkClient`. The real client
/// reads this from `UserDefaults` + Keychain; tests pass in literal values.
///
/// `fallbackBaseURL` is an optional second network path to the same printer.
/// When set, the client retries on `.unreachable` against the alternate URL
/// using the same `apiKey` and `timeout`. Default nil keeps existing call
/// sites source-compatible.
public struct PrusaLinkConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var fallbackBaseURL: URL?
    public var apiKey: String
    public var timeout: TimeInterval

    public init(
        baseURL: URL,
        apiKey: String,
        fallbackBaseURL: URL? = nil,
        timeout: TimeInterval = 5
    ) {
        self.baseURL = baseURL
        self.fallbackBaseURL = fallbackBaseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }
}
