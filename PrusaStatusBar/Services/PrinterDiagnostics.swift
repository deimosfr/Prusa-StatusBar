import Foundation

/// Sanitized, shareable responses collected from an authenticated printer.
/// Raw response bytes never leave the network client.
public struct PrinterDiagnosticSnapshot: Sendable, Equatable {
    public let infoJSON: String
    public let statusJSON: String
    public let jobJSON: String?
    public let versionJSON: String?
    public let printerJSON: String?

    init(info: Data, status: Data, job: Data?, version: Data?, printer: Data?) throws {
        infoJSON = try Self.redactedJSON(from: info)
        statusJSON = try Self.redactedJSON(from: status)
        jobJSON = job.flatMap { try? Self.redactedJSON(from: $0) }
        versionJSON = version.flatMap { try? Self.redactedJSON(from: $0) }
        printerJSON = printer.flatMap { try? Self.redactedJSON(from: $0) }
    }

    func markdown(
        showNozzleDiameter: Bool,
        configuredNozzleDiameters: [Double],
        effectiveNozzleDiameters: [Double]
    ) -> String {
        let version = AppVersion.shortString ?? "?"
        let build = AppVersion.buildNumber ?? "?"
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let nozzleMode = if configuredNozzleDiameters.isEmpty {
            "Automatic (PrusaLink)"
        } else {
            "Manual: " + Self.nozzleList(configuredNozzleDiameters)
        }

        return """
        ## Prusa StatusBar diagnostic

        - Generated: \(generatedAt)
        - App: \(version) (\(build))
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Architecture: \(Self.architecture)
        - Locale: \(Locale.current.identifier)
        - Printer API access: Verified
        - Nozzle diameter display: \(showNozzleDiameter ? "Enabled" : "Disabled")
        - Nozzle configuration: \(nozzleMode)
        - Effective nozzle diameters: \(Self.nozzleList(effectiveNozzleDiameters))

        ### `GET /api/v1/info`

        ```json
        \(infoJSON)
        ```

        ### `GET /api/version`

        \(Self.endpointSection(versionJSON))

        ### `GET /api/v1/status`

        ```json
        \(statusJSON)
        ```

        ### `GET /api/printer`

        \(Self.endpointSection(printerJSON))

        ### `GET /api/v1/job`

        \(Self.endpointSection(jobJSON, unavailable: "No active print job or endpoint unavailable."))
        """
    }

    private static func endpointSection(
        _ json: String?,
        unavailable: String = "Endpoint unavailable on this firmware."
    ) -> String {
        guard let json else {
            return "_\(unavailable)_"
        }
        return """
        ```json
        \(json)
        ```
        """
    }

    private static func nozzleList(_ diameters: [Double]) -> String {
        guard !diameters.isEmpty else {
            return "None"
        }
        return diameters.enumerated()
            .map { "Tool \($0.offset + 1) \(String(format: "%.2f mm", $0.element))" }
            .joined(separator: ", ")
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }

    private static let sensitiveKeyFragments = [
        "address", "apikey", "authorization", "cookie", "credential",
        "displayname", "download", "hostname", "icon", "mac", "name",
        "password", "path", "secret", "serial", "thumbnail", "token",
        "uri", "url", "username", "uuid"
    ]

    private static func redactedJSON(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let redacted = redact(object)
        let output = try JSONSerialization.data(
            withJSONObject: redacted,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let json = String(data: output, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return json
    }

    private static func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = isSensitiveKey(item.key) ? "[redacted]" : redact(item.value)
            }
        }
        if let array = value as? [Any] {
            return array.map(redact)
        }
        if let string = value as? String, containsAddress(string) {
            return "[redacted]"
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return sensitiveKeyFragments.contains { normalized.contains($0) }
    }

    private static func containsAddress(_ value: String) -> Bool {
        let patterns = [
            #"(?i)\b(?:https?|rtsp)://"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            #"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"#
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }
}

public enum PrinterDiagnosticsError: Error, Equatable, Sendable {
    case printer(PrusaLinkError)
    case invalidResponse
}
