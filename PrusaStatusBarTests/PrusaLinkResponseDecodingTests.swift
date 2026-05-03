import Foundation
@testable import PrusaStatusBar
import Testing

/// Spec coverage:
/// - `prusa-link-client` Requirement: Client polls printer status
/// - `prusa-link-client` Requirement: Client fetches current job detail
/// Sample payloads are taken straight from the PrusaLink OpenAPI examples and
/// from the original Rust i3blocks integration to keep us bug-compatible.
struct PrusaLinkResponseDecodingTests {
    private func decodeStatus(_ json: String) throws -> StatusEnvelopeDTO {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(StatusEnvelopeDTO.self, from: data)
    }

    private func decodeJob(_ json: String) throws -> JobDetailDTO {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(JobDetailDTO.self, from: data)
    }

    // MARK: - Status

    @Test
    func decodesPrintingPayload() throws {
        let payload = """
        {
          "job": {
            "id": 12,
            "progress": 62.0,
            "time_printing": 59544,
            "time_remaining": 34320
          },
          "printer": {
            "axis_z": 121.8,
            "fan_hotend": 8111,
            "fan_print": 6105,
            "flow": 100,
            "speed": 100,
            "state": "PRINTING",
            "target_bed": 60,
            "target_nozzle": 220,
            "temp_bed": 60,
            "temp_nozzle": 219.2
          }
        }
        """
        let dto = try decodeStatus(payload)
        let status = PrusaLinkResponseMapper.map(dto)
        #expect(status.state == .printing)
        #expect(status.progress == 0.62)
        #expect(status.timeRemaining == 34320)
        #expect(status.timePrinting == 59544)
        #expect(status.nozzleTemperature == Temperature(current: 219.2, target: 220))
        #expect(status.bedTemperature == Temperature(current: 60, target: 60))
        #expect(status.speed == 100)
        #expect(status.zHeight == 121.8)
    }

    @Test
    func decodesInfoWithNozzleDiameter() throws {
        let payload = """
        {
          "name": "MuadDib",
          "hostname": "prusa-mk3.lan",
          "serial": "MK3S-12345",
          "nozzle_diameter": 0.4
        }
        """
        let data = try #require(payload.data(using: .utf8))
        let dto = try JSONDecoder().decode(InfoDTO.self, from: data)
        let info = PrusaLinkResponseMapper.map(dto)
        #expect(info.name == "MuadDib")
        #expect(info.hostname == "prusa-mk3.lan")
        #expect(info.serial == "MK3S-12345")
        #expect(info.nozzleDiameter == 0.4)
    }

    @Test
    func decodesInfoWithoutNozzleDiameter() throws {
        let payload = """
        { "name": "MuadDib", "hostname": "prusa-mk3.lan", "serial": "MK3S-12345" }
        """
        let data = try #require(payload.data(using: .utf8))
        let dto = try JSONDecoder().decode(InfoDTO.self, from: data)
        let info = PrusaLinkResponseMapper.map(dto)
        #expect(info.nozzleDiameter == nil)
    }

    @Test
    func decodesFinishedPayloadWithoutJob() throws {
        let payload = """
        {
          "printer": {
            "state": "FINISHED",
            "temp_bed": 52.3,
            "target_bed": 0.0,
            "temp_nozzle": 98.3,
            "target_nozzle": 0.0
          }
        }
        """
        let dto = try decodeStatus(payload)
        let status = PrusaLinkResponseMapper.map(dto)
        #expect(status.state == .finished)
        #expect(status.progress == 1.0)
        #expect(status.timeRemaining == nil)
    }

    @Test
    func decodesIdlePayload() throws {
        let payload = """
        { "printer": { "state": "IDLE" } }
        """
        let dto = try decodeStatus(payload)
        let status = PrusaLinkResponseMapper.map(dto)
        #expect(status.state == .idle)
        #expect(status.progress == nil)
        #expect(status.timeRemaining == nil)
        #expect(status.nozzleTemperature == nil)
    }

    @Test
    func decodesAttentionTypoVariant() throws {
        let payload = """
        {
          "job": { "id": 1, "progress": 50, "time_printing": 100, "time_remaining": 50 },
          "printer": { "state": "ATTTENTION" }
        }
        """
        let dto = try decodeStatus(payload)
        let status = PrusaLinkResponseMapper.map(dto)
        #expect(status.state == .attention)
        #expect(status.progress == 0.5)
    }

    @Test
    func progressIsClampedTo0_1() throws {
        // Defensive: PrusaLink should never send 0..>100, but if it does we
        // should not surface absurd values to the UI.
        let payload = """
        {
          "job": { "id": 1, "progress": 142, "time_printing": 0, "time_remaining": 0 },
          "printer": { "state": "PRINTING" }
        }
        """
        let dto = try decodeStatus(payload)
        let status = PrusaLinkResponseMapper.map(dto)
        #expect(status.progress == 1.0)
    }

    // MARK: - Job

    @Test
    func decodesJobWithThumbnail() throws {
        let payload = """
        {
          "id": 42,
          "state": "PRINTING",
          "progress": 12.5,
          "time_printing": 100,
          "file": {
            "name": "SPICE~1.GCO",
            "display_name": "Spice_Harvester_0.3mm_PLA_MK3S_12m.gcode",
            "path": "/local",
            "refs": {
              "download": "/api/files/local/spice.gcode/raw",
              "icon": "/api/thumbnails/local/spice.gcode.small.png",
              "thumbnail": "/api/thumbnails/local/spice.gcode.orig.png"
            }
          }
        }
        """
        let dto = try decodeJob(payload)
        let job = PrusaLinkResponseMapper.map(dto)
        #expect(job?.displayName == "Spice_Harvester_0.3mm_PLA_MK3S_12m.gcode")
        #expect(job?.thumbnailPath == "/api/thumbnails/local/spice.gcode.orig.png")
        #expect(job?.id == 42)
    }

    @Test
    func decodesJobWithoutId() throws {
        let payload = """
        {
          "state": "PRINTING",
          "progress": 12.5,
          "file": {
            "name": "no-id.gcode",
            "display_name": "no-id.gcode"
          }
        }
        """
        let dto = try decodeJob(payload)
        let job = PrusaLinkResponseMapper.map(dto)
        #expect(job?.id == nil)
        #expect(job?.displayName == "no-id.gcode")
    }

    @Test
    func jobWithoutFileBlockReturnsNil() throws {
        let payload = """
        { "id": 42, "state": "PRINTING", "progress": 12.5 }
        """
        let dto = try decodeJob(payload)
        let job = PrusaLinkResponseMapper.map(dto)
        #expect(job == nil)
    }
}

/// Spec coverage:
/// - `prusa-link-client` Requirement: Client decodes active filament material
///   from legacy endpoint
/// - `prusa-link-client` Requirement: Client decodes MMU presence
/// Carved out of `PrusaLinkResponseDecodingTests` to keep the parent suite
/// under SwiftLint's `type_body_length` ceiling.
struct PrusaLinkSlotAndMMUDecodingTests {
    private func decodeLegacy(_ json: String) throws -> LegacyPrinterDTO {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(LegacyPrinterDTO.self, from: data)
    }

    private func decodeInfo(_ json: String) throws -> InfoDTO {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(InfoDTO.self, from: data)
    }

    // MARK: - Legacy filament material

    @Test
    func decodesLegacyMaterial_loaded() throws {
        let dto = try decodeLegacy("""
        { "telemetry": { "material": "PLA" } }
        """)
        #expect(PrusaLinkResponseMapper.map(dto) == "PLA")
    }

    @Test
    func decodesLegacyMaterial_missingTelemetry() throws {
        let dto = try decodeLegacy("{}")
        #expect(PrusaLinkResponseMapper.map(dto) == nil)
    }

    @Test
    func decodesLegacyMaterial_missingMaterial() throws {
        let dto = try decodeLegacy("""
        { "telemetry": {} }
        """)
        #expect(PrusaLinkResponseMapper.map(dto) == nil)
    }

    @Test
    func decodesLegacyMaterial_emptyString() throws {
        let dto = try decodeLegacy("""
        { "telemetry": { "material": "   " } }
        """)
        #expect(PrusaLinkResponseMapper.map(dto) == nil)
    }

    // MARK: - MMU flag

    @Test
    func decodesMMUFlag_boolTrue() throws {
        let info = try PrusaLinkResponseMapper.map(decodeInfo("""
        { "name": "X", "mmu": true }
        """))
        #expect(info.mmuEnabled == true)
    }

    @Test
    func decodesMMUFlag_boolFalse() throws {
        let info = try PrusaLinkResponseMapper.map(decodeInfo("""
        { "name": "X", "mmu": false }
        """))
        #expect(info.mmuEnabled == false)
    }

    @Test
    func decodesMMUFlag_objectEnabledTrue() throws {
        let info = try PrusaLinkResponseMapper.map(decodeInfo("""
        { "name": "X", "mmu": { "enabled": true, "version": 3 } }
        """))
        #expect(info.mmuEnabled == true)
    }

    @Test
    func decodesMMUFlag_objectEnabledFalse() throws {
        let info = try PrusaLinkResponseMapper.map(decodeInfo("""
        { "name": "X", "mmu": { "enabled": false, "version": 3 } }
        """))
        #expect(info.mmuEnabled == false)
    }

    @Test
    func decodesMMUFlag_absent() throws {
        let info = try PrusaLinkResponseMapper.map(decodeInfo("""
        { "name": "X" }
        """))
        #expect(info.mmuEnabled == nil)
    }
}
