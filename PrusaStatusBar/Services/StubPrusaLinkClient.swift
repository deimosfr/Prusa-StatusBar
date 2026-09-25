import Foundation

/// In-memory `PrusaLinkClient` used by prototype mode and tests. Plays a
/// scripted state stream: Idle -> Printing (progress climbing) -> Finished,
/// so the UI can be reviewed without a real printer.
///
/// All methods are actor-isolated (the protocol is `async`, so callers `await`
/// implicitly). An earlier draft marked them `nonisolated` but then needed to
/// `await` every helper anyway, keeping the methods isolated keeps the
/// implementation straight-line and Swift 6-clean.
public actor StubPrusaLinkClient: PrusaLinkClient {
    public enum Phase: Sendable {
        case idle
        case printing(progress: Double)
        case attention
        case finished
    }

    private var phase: Phase
    private var stepCount: Int = 0

    public init(phase: Phase = .printing(progress: 0.05)) {
        self.phase = phase
    }

    public func fetchStatus() async -> Result<PrinterStatus, PrusaLinkError> {
        tick()
        return .success(snapshot())
    }

    public func fetchJob() async -> Result<PrintJob?, PrusaLinkError> {
        switch phase {
        case .idle:
            .success(nil)
        case .printing, .attention, .finished:
            .success(PrintJob(
                displayName: "Spice_Harvester_0.3mm_PLA_MK3S_12m.gcode",
                thumbnailPath: nil,
                id: 1
            ))
        }
    }

    public func fetchThumbnail(at path: String) async -> Result<Data, PrusaLinkError> {
        _ = path
        return .failure(.notFound)
    }

    public func fetchInfo() async -> Result<PrinterInfo, PrusaLinkError> {
        .success(PrinterInfo(
            name: "MuadDib (stub)",
            hostname: "stub.local",
            serial: "STUB-0001",
            nozzleDiameter: 0.4,
            mmuEnabled: true
        ))
    }

    public func fetchDiagnosticSnapshot() async -> Result<PrinterDiagnosticSnapshot, PrinterDiagnosticsError> {
        let info = Data(#"{"nozzle_diameter":0.4,"serial":"STUB-0001","hostname":"stub.local"}"#.utf8)
        let status = Data(#"{"printer":{"state":"PRINTING","temp_nozzle":215}}"#.utf8)
        let job: Data? = if case .idle = phase {
            nil
        } else {
            Data(#"{"file":{"display_name":"Spice_Harvester.gcode","path":"/usb/Spice_Harvester.gcode"}}"#.utf8)
        }
        let version = Data(#"{"firmware":"6.4.2","printer":"17.0.0"}"#.utf8)
        let printer = Data(#"{"telemetry":{"material":"PLA"},"state":{"text":"Printing"}}"#.utf8)
        return Result {
            try PrinterDiagnosticSnapshot(
                info: info,
                status: status,
                job: job,
                version: version,
                printer: printer
            )
        }
        .mapError { _ in .invalidResponse }
    }

    public func fetchLegacyMaterial() async -> Result<String?, PrusaLinkError> {
        switch phase {
        case .printing, .attention:
            .success("PLA")
        case .idle, .finished:
            .success(nil)
        }
    }

    public func resumeJob(id _: Int) async -> Result<Void, PrusaLinkError> {
        switch phase {
        case .attention:
            phase = .printing(progress: 0.5)
        case .idle, .printing, .finished:
            break
        }
        return .success(())
    }

    public func pauseJob(id _: Int) async -> Result<Void, PrusaLinkError> {
        .success(())
    }

    public func stopJob(id _: Int) async -> Result<Void, PrusaLinkError> {
        phase = .idle
        return .success(())
    }

    // MARK: - State stream

    private func tick() {
        stepCount += 1
        switch phase {
        case .idle:
            if stepCount >= 1 {
                phase = .printing(progress: 0.05)
            }
        case let .printing(progress):
            let next = progress + 0.07
            phase = next >= 1.0 ? .finished : .printing(progress: next)
        case .attention:
            phase = .printing(progress: 0.5)
        case .finished:
            break
        }
    }

    private func snapshot() -> PrinterStatus {
        switch phase {
        case .idle:
            return PrinterStatus(
                state: .idle,
                nozzleTemperature: Temperature(current: 24.5, target: 0),
                bedTemperature: Temperature(current: 23.8, target: 0)
            )
        case let .printing(progress):
            let totalSeconds: TimeInterval = 60 * 60 * 3
            let elapsed = totalSeconds * progress
            let remaining = totalSeconds - elapsed
            return PrinterStatus(
                state: .printing,
                progress: progress,
                timeRemaining: remaining,
                timePrinting: elapsed,
                nozzleTemperature: Temperature(current: 215, target: 215),
                bedTemperature: Temperature(current: 60, target: 60),
                speed: 100,
                zHeight: 12.45 + progress * 30
            )
        case .attention:
            return PrinterStatus(
                state: .attention,
                progress: 0.5,
                timeRemaining: 60 * 30,
                timePrinting: 60 * 60,
                nozzleTemperature: Temperature(current: 210, target: 215),
                bedTemperature: Temperature(current: 60, target: 60),
                speed: 100,
                zHeight: 18.7
            )
        case .finished:
            return PrinterStatus(
                state: .finished,
                progress: 1.0,
                timeRemaining: 0,
                timePrinting: 60 * 60 * 3,
                nozzleTemperature: Temperature(current: 90, target: 0),
                bedTemperature: Temperature(current: 50, target: 0)
            )
        }
    }
}
