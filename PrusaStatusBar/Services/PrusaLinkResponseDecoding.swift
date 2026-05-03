import Foundation

// MARK: - Wire DTOs

/// Wire model for `GET /api/v1/status`. `printer` is the only required field;
/// everything else is optional per the OpenAPI spec.
struct StatusEnvelopeDTO: Decodable {
    let job: JobDTO?
    let printer: PrinterDTO

    struct JobDTO: Decodable {
        let id: Int?
        let progress: Double?
        let timeRemaining: TimeInterval?
        let timePrinting: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case id
            case progress
            case timeRemaining = "time_remaining"
            case timePrinting = "time_printing"
        }
    }

    struct PrinterDTO: Decodable {
        let state: String
        let tempNozzle: Double?
        let targetNozzle: Double?
        let tempBed: Double?
        let targetBed: Double?
        let speed: Double?
        let axisZ: Double?

        enum CodingKeys: String, CodingKey {
            case state
            case tempNozzle = "temp_nozzle"
            case targetNozzle = "target_nozzle"
            case tempBed = "temp_bed"
            case targetBed = "target_bed"
            case speed
            case axisZ = "axis_z"
        }
    }
}

/// Wire model for the OctoPrint-compatible `GET /api/printer` endpoint.
/// Used solely to surface `telemetry.material`; PrusaLink's own
/// `/api/v1/status` does not include the loaded filament on most firmware,
/// matching the path the Home Assistant PrusaLink integration takes.
struct LegacyPrinterDTO: Decodable {
    let telemetry: TelemetryDTO?

    struct TelemetryDTO: Decodable {
        let material: String?
    }
}

/// Wire model for `GET /api/v1/job`.
struct JobDetailDTO: Decodable {
    let id: Int?
    let state: String?
    let progress: Double?
    let file: FileDTO?

    struct FileDTO: Decodable {
        let name: String?
        let displayName: String?
        let refs: RefsDTO?

        enum CodingKeys: String, CodingKey {
            case name
            case displayName = "display_name"
            case refs
        }
    }

    struct RefsDTO: Decodable {
        let download: String?
        let icon: String?
        let thumbnail: String?
    }
}

/// Wire model for `GET /api/v1/info`.
struct InfoDTO: Decodable {
    let name: String?
    let hostname: String?
    let serial: String?
    let nozzleDiameter: Double?
    let mmu: MMUFlagDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case hostname
        case serial
        case nozzleDiameter = "nozzle_diameter"
        case mmu
    }
}

/// PrusaLink reports `mmu` either as a bare `Bool` (older firmware, e.g.
/// MK4 5.x) or as `{ "enabled": Bool, "version": Int }` (newer firmware,
/// MK4 6.x and XL). Both shapes collapse to a single `enabled` flag.
enum MMUFlagDTO: Decodable {
    case bool(Bool)
    case object(enabled: Bool)

    var enabled: Bool {
        switch self {
        case let .bool(value):
            value
        case let .object(enabled):
            enabled
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(Bool.self) {
            self = .bool(value)
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try keyed.decode(Bool.self, forKey: .enabled)
        self = .object(enabled: enabled)
    }
}

// MARK: - DTO → domain

enum PrusaLinkResponseMapper {
    /// Maps the wire envelope into the `PrinterStatus` domain value.
    /// Normalises the 0...100 percentage to 0...1 and forces `progress` to
    /// 1.0 when the printer reports `.finished` (matching the i3blocks Rust
    /// reference and the spec's "Printer reports finished" scenario).
    static func map(_ dto: StatusEnvelopeDTO) -> PrinterStatus {
        let state = PrinterState.decode(dto.printer.state)

        let progress: Double? = {
            if state == .finished {
                return 1.0
            }
            guard let raw = dto.job?.progress else {
                return nil
            }
            return max(0.0, min(1.0, raw / 100.0))
        }()

        let nozzle: Temperature? = {
            guard let current = dto.printer.tempNozzle else {
                return nil
            }
            return Temperature(current: current, target: dto.printer.targetNozzle ?? 0)
        }()

        let bed: Temperature? = {
            guard let current = dto.printer.tempBed else {
                return nil
            }
            return Temperature(current: current, target: dto.printer.targetBed ?? 0)
        }()

        return PrinterStatus(
            state: state,
            progress: progress,
            timeRemaining: dto.job?.timeRemaining,
            timePrinting: dto.job?.timePrinting,
            nozzleTemperature: nozzle,
            bedTemperature: bed,
            speed: dto.printer.speed,
            zHeight: dto.printer.axisZ
        )
    }

    /// Trims whitespace and treats empty as nil so the dropdown row hides
    /// cleanly when the printer reports an empty `material` string.
    static func map(_ dto: LegacyPrinterDTO) -> String? {
        let raw = dto.telemetry?.material?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// `nil` means "no job to report" (the caller maps HTTP 204 to nil before
    /// calling here). When the file block is missing, we still surface a
    /// `PrintJob` with a fallback display name so the UI has something to render.
    static func map(_ dto: JobDetailDTO) -> PrintJob? {
        guard let file = dto.file else {
            return nil
        }
        let name = file.displayName ?? file.name ?? "Unnamed file"
        return PrintJob(displayName: name, thumbnailPath: file.refs?.thumbnail, id: dto.id)
    }

    static func map(_ dto: InfoDTO) -> PrinterInfo {
        PrinterInfo(
            name: dto.name,
            hostname: dto.hostname,
            serial: dto.serial,
            nozzleDiameter: dto.nozzleDiameter,
            mmuEnabled: dto.mmu?.enabled
        )
    }
}
