import Foundation

extension URLSessionPrusaLinkClient {
    public func fetchDiagnosticSnapshot() async -> Result<PrinterDiagnosticSnapshot, PrinterDiagnosticsError> {
        let statusResponse: DiagnosticResponse
        switch await fetchDiagnosticResponse(path: "/api/v1/status") {
        case let .success(response):
            statusResponse = response
        case let .failure(error):
            return .failure(.printer(error))
        }

        let infoResponse: DiagnosticResponse
        switch await fetchDiagnosticResponse(path: "/api/v1/info") {
        case let .success(response):
            infoResponse = response
        case let .failure(error):
            return .failure(.printer(error))
        }

        let versionData = await fetchOptionalDiagnosticData(path: "/api/version")
        let printerData = await fetchOptionalDiagnosticData(path: "/api/printer")
        let jobData = await fetchOptionalDiagnosticData(path: "/api/v1/job")

        do {
            return try .success(PrinterDiagnosticSnapshot(
                info: infoResponse.data,
                status: statusResponse.data,
                job: jobData,
                version: versionData,
                printer: printerData
            ))
        } catch {
            return .failure(.invalidResponse)
        }
    }

    private func fetchDiagnosticResponse(path: String) async -> Result<DiagnosticResponse, PrusaLinkError> {
        await perform(path: path) { status, data in
            guard (200 ... 299).contains(status) else {
                return .failure(.server(status: status))
            }
            return .success(DiagnosticResponse(status: status, data: data))
        }
    }

    private func fetchOptionalDiagnosticData(path: String) async -> Data? {
        guard case let .success(response) = await fetchDiagnosticResponse(path: path),
              response.status != 204,
              !response.data.isEmpty
        else {
            return nil
        }
        return response.data
    }
}

private struct DiagnosticResponse: Sendable {
    let status: Int
    let data: Data
}
