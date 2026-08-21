import Foundation
@testable import PrusaStatusBar
import Testing

struct PrinterDiagnosticsTests {
    private func makeClient(
        handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Response
    ) -> URLSessionPrusaLinkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = handler
        return URLSessionPrusaLinkClient(session: session) {
            PrusaLinkConfiguration(baseURL: URL(string: "http://printer.local")!, apiKey: "test-key")
        }
    }

    @Test
    func copyableDiagnosticsRedactSensitiveResponses() async {
        let client = makeClient { request in
            let body: String
            switch request.url?.path {
            case "/api/v1/info":
                body = #"{"hostname":"private.local","serial":"SN-123","nozzle_diameter":0.4}"#
            case "/api/version":
                body = #"{"hostname":"private.local","firmware":"6.4.2","printer":"17.0.0"}"#
            case "/api/v1/status":
                body = #"{"printer":{"state":"PRINTING","temp_nozzle":215,"note":"http://192.168.1.5/private"}}"#
            case "/api/printer":
                body = #"{"telemetry":{"material":"PLA"},"state":{"text":"Printing"}}"#
            case "/api/v1/job":
                body = #"{"file":{"display_name":"private-part.gcode","path":"/usb/private-part.gcode"}}"#
            default:
                return .response(status: 404, body: Data())
            }
            return .response(status: 200, body: Data(body.utf8))
        }

        let result = await client.fetchDiagnosticSnapshot()
        guard case let .success(snapshot) = result else {
            Issue.record("Expected diagnostics, got \(result)")
            return
        }

        let report = snapshot.markdown(
            showNozzleDiameter: true,
            configuredNozzleDiameters: [],
            effectiveNozzleDiameters: [0.4]
        )
        #expect(report.contains("private.local") == false)
        #expect(report.contains("SN-123") == false)
        #expect(report.contains("private-part.gcode") == false)
        #expect(report.contains("192.168.1.5") == false)
        #expect(report.contains("PRINTING"))
        #expect(report.contains("0.4"))
        #expect(report.contains("6.4.2"))
        #expect(report.contains("17.0.0"))
        #expect(report.contains("material"))
    }

    @Test
    func diagnosticsAreAvailableWithoutAnActivePrint() async {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/v1/status":
                .response(status: 200, body: Data(#"{"printer":{"state":"IDLE"}}"#.utf8))
            case "/api/v1/info":
                .response(status: 200, body: Data(#"{"nozzle_diameter":0.4}"#.utf8))
            case "/api/v1/job":
                .response(status: 204, body: Data())
            default:
                .response(status: 404, body: Data())
            }
        }

        let result = await client.fetchDiagnosticSnapshot()
        guard case let .success(snapshot) = result else {
            Issue.record("Expected diagnostics, got \(result)")
            return
        }
        #expect(snapshot.jobJSON == nil)
        let report = snapshot.markdown(
            showNozzleDiameter: true,
            configuredNozzleDiameters: [],
            effectiveNozzleDiameters: [0.4]
        )
        #expect(report.contains("No active print job or endpoint unavailable."))
        #expect(report.contains("Endpoint unavailable on this firmware."))
    }
}
