import Foundation

/// All printer states reported by PrusaLink's `/api/v1/status`.
///
/// Mirrors the `state` enum from the OpenAPI spec; note the upstream typo
/// `ATTTENTION` (three Ts) which we accept and normalise to `.attention`.
public enum PrinterState: String, Sendable, CaseIterable, Equatable {
    case idle
    case busy
    case printing
    case paused
    case finished
    case stopped
    case error
    case attention
    case ready

    /// Decode a raw value from the API, tolerating mixed casing and the upstream
    /// `ATTTENTION` typo. Returns `.idle` as a safe fallback for unknown values
    /// rather than throwing; the caller decides how to surface that.
    public static func decode(_ raw: String) -> PrinterState {
        switch raw.uppercased() {
        case "IDLE":
            .idle
        case "BUSY":
            .busy
        case "PRINTING":
            .printing
        case "PAUSED":
            .paused
        case "FINISHED":
            .finished
        case "STOPPED":
            .stopped
        case "ERROR":
            .error
        case "ATTENTION", "ATTTENTION":
            .attention
        case "READY":
            .ready
        default:
            .idle
        }
    }

    /// True when the printer is actively working on a job, used by the polling
    /// loop to choose the fast cadence.
    public var isActive: Bool {
        switch self {
        case .printing, .paused, .attention, .busy:
            true
        case .idle, .ready, .finished, .stopped, .error:
            false
        }
    }

    /// True when the printer is in a terminal state (the job has ended).
    public var isTerminal: Bool {
        switch self {
        case .finished, .stopped, .error:
            true
        default:
            false
        }
    }
}
