import Foundation

/// Decoded snapshot returned by `PrusaLinkClient.fetchStatus()`.
///
/// `progress` is normalised to the 0...1 range (PrusaLink reports a percentage
/// 0...100 in the wire format). All time fields are seconds.
public struct PrinterStatus: Sendable, Equatable {
    public var state: PrinterState
    public var progress: Double?
    public var timeRemaining: TimeInterval?
    public var timePrinting: TimeInterval?

    public var nozzleTemperature: Temperature?
    public var bedTemperature: Temperature?

    /// Live print-speed override percentage reported by `printer.speed`.
    /// 100 means "print at the file's native speed".
    public var speed: Double?

    /// Current Z-axis height in millimetres, from `printer.axis_z`.
    public var zHeight: Double?

    /// Material loaded in the active extruder slot (e.g. `"PLA"`, `"PETG"`),
    /// from `slot.slots[slot.active].material`. `nil` when the firmware
    /// omits the slot block, when no slot is loaded, or when the material
    /// string is empty.
    public var activeFilamentMaterial: String?

    public init(
        state: PrinterState,
        progress: Double? = nil,
        timeRemaining: TimeInterval? = nil,
        timePrinting: TimeInterval? = nil,
        nozzleTemperature: Temperature? = nil,
        bedTemperature: Temperature? = nil,
        speed: Double? = nil,
        zHeight: Double? = nil,
        activeFilamentMaterial: String? = nil
    ) {
        self.state = state
        self.progress = progress
        self.timeRemaining = timeRemaining
        self.timePrinting = timePrinting
        self.nozzleTemperature = nozzleTemperature
        self.bedTemperature = bedTemperature
        self.speed = speed
        self.zHeight = zHeight
        self.activeFilamentMaterial = activeFilamentMaterial
    }
}

/// Pair of current/target temperature values for a heated component.
public struct Temperature: Sendable, Equatable {
    public var current: Double
    public var target: Double

    public init(current: Double, target: Double) {
        self.current = current
        self.target = target
    }
}

/// Decoded snapshot returned by `PrusaLinkClient.fetchJob()`. `nil` is used
/// at the call-site to mean "no job currently active" (HTTP 204).
public struct PrintJob: Sendable, Equatable {
    public var displayName: String
    public var thumbnailPath: String?
    /// Upstream PrusaLink job id, needed to target the job-control
    /// endpoints (`/api/v1/job/{id}/{pause,resume}` and `DELETE
    /// /api/v1/job/{id}`). Optional because some payloads may omit it.
    public var id: Int?

    public init(displayName: String, thumbnailPath: String? = nil, id: Int? = nil) {
        self.displayName = displayName
        self.thumbnailPath = thumbnailPath
        self.id = id
    }
}

/// Decoded snapshot returned by `PrusaLinkClient.fetchInfo()`. Used by the
/// "Test connection" button in Preferences.
public struct PrinterInfo: Sendable, Equatable {
    public var name: String?
    public var hostname: String?
    public var serial: String?
    public var nozzleDiameter: Double?
    /// `nil` when `/api/v1/info` does not surface an `mmu` field at all
    /// (e.g. MK3S firmware), so callers can hide the MMU row entirely
    /// rather than reporting "Disabled" for hardware that lacks the slot.
    public var mmuEnabled: Bool?

    public init(
        name: String? = nil,
        hostname: String? = nil,
        serial: String? = nil,
        nozzleDiameter: Double? = nil,
        mmuEnabled: Bool? = nil
    ) {
        self.name = name
        self.hostname = hostname
        self.serial = serial
        self.nozzleDiameter = nozzleDiameter
        self.mmuEnabled = mmuEnabled
    }
}
