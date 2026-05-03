import Foundation

/// One of six fixed dropdown slots a custom HTTP action can occupy:
/// two icon-only buttons in the hero header (`headerLeft`, `headerRight`),
/// a middle content row of icon + text buttons (`rowSecondLeft`,
/// `rowSecondRight`) mounted inside the content body directly after the
/// last camera tile, and a bottom content row (`rowLeft`, `rowRight`)
/// inserted between `LinksRow` and the footer. Each row collapses
/// independently. Case declaration order = settings card order: header,
/// middle, bottom.
public enum CustomActionSlot: String, CaseIterable, Codable, Sendable, Hashable {
    case headerLeft
    case headerRight
    case rowSecondLeft
    case rowSecondRight
    case rowLeft
    case rowRight

    public var isHeader: Bool {
        switch self {
        case .headerLeft, .headerRight: true
        case .rowLeft, .rowRight, .rowSecondLeft, .rowSecondRight: false
        }
    }
}

public enum CustomActionMethod: String, CaseIterable, Codable, Sendable, Hashable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// Per-slot connection-state visibility gate. Evaluated cheaply against the
/// dropdown's current presentation; lives in the non-sensitive half so the
/// dropdown never has to unlock the Keychain to know whether to render a
/// slot.
public enum CustomActionVisibility: String, CaseIterable, Codable, Sendable, Hashable {
    case always
    case whenConnected
    case whenDisconnected
}

/// Stable identity for a header row in a `CustomActionConfig`. The id is
/// shared between the public half (header name) and the secrets half
/// (header value) so they can be reassembled at read time even after the
/// user reorders or removes rows.
public struct CustomActionHeader: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// Full in-memory view of a slot. The persisted form is split into
/// `CustomActionPublicConfig` (always in `UserDefaults`) and
/// `CustomActionSecrets` (Keychain when the toggle is on, plaintext slot
/// otherwise). UI binds against this assembled value.
public struct CustomActionConfig: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var name: String
    public var symbol: String
    public var method: CustomActionMethod
    public var visibility: CustomActionVisibility
    public var confirmBeforeRun: Bool
    public var url: String
    public var headers: [CustomActionHeader]
    public var body: String

    public init(
        enabled: Bool = false,
        name: String = "",
        symbol: String = "",
        method: CustomActionMethod = .post,
        visibility: CustomActionVisibility = .always,
        confirmBeforeRun: Bool = false,
        url: String = "",
        headers: [CustomActionHeader] = [],
        body: String = ""
    ) {
        self.enabled = enabled
        self.name = name
        self.symbol = symbol
        self.method = method
        self.visibility = visibility
        self.confirmBeforeRun = confirmBeforeRun
        self.url = url
        self.headers = headers
        self.body = body
    }

    public static let `default` = CustomActionConfig()

    /// True iff the slot is enabled and has the minimum data required to
    /// fire (a non-empty URL). UI uses this to render the per-card status
    /// dot (green vs amber vs gray).
    public var isValid: Bool {
        guard enabled else { return false }
        return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Non-sensitive half of `CustomActionConfig`. Stored as JSON in
/// `UserDefaults`. The dropdown reads this on every popover open without
/// touching the Keychain so unlocking is deferred to action-fire time.
public struct CustomActionPublicConfig: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var name: String
    public var symbol: String
    public var method: CustomActionMethod
    public var visibility: CustomActionVisibility
    public var confirmBeforeRun: Bool
    /// Header *names* only (paired with secret values by `id` at assembly).
    public var headerNames: [PublicHeaderEntry]

    public struct PublicHeaderEntry: Codable, Hashable, Sendable {
        public let id: UUID
        public var name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public init(
        enabled: Bool = false,
        name: String = "",
        symbol: String = "",
        method: CustomActionMethod = .post,
        visibility: CustomActionVisibility = .always,
        confirmBeforeRun: Bool = false,
        headerNames: [PublicHeaderEntry] = []
    ) {
        self.enabled = enabled
        self.name = name
        self.symbol = symbol
        self.method = method
        self.visibility = visibility
        self.confirmBeforeRun = confirmBeforeRun
        self.headerNames = headerNames
    }
}

/// Sensitive half of `CustomActionConfig`. Stored in the Keychain when
/// the user has the "Store sensitive info in macOS Keychain" toggle ON,
/// otherwise in a per-slot plaintext `UserDefaults` entry. URL is
/// considered sensitive because tokens are commonly embedded in query
/// strings (HomeAssistant webhooks especially).
public struct CustomActionSecrets: Codable, Hashable, Sendable {
    public var url: String
    public var body: String
    /// Map of `headerNames[i].id -> value`. UUID keys keep header values
    /// glued to their public name even after reordering.
    public var headerValues: [String: String]

    public init(url: String = "", body: String = "", headerValues: [String: String] = [:]) {
        self.url = url
        self.body = body
        self.headerValues = headerValues
    }
}

public extension CustomActionConfig {
    /// Split into the persisted halves at save time.
    func split() -> (CustomActionPublicConfig, CustomActionSecrets) {
        let publicEntries = headers.map { CustomActionPublicConfig.PublicHeaderEntry(id: $0.id, name: $0.name) }
        let pub = CustomActionPublicConfig(
            enabled: enabled,
            name: name,
            symbol: symbol,
            method: method,
            visibility: visibility,
            confirmBeforeRun: confirmBeforeRun,
            headerNames: publicEntries
        )
        var values: [String: String] = [:]
        for header in headers where !header.value.isEmpty {
            values[header.id.uuidString] = header.value
        }
        let secrets = CustomActionSecrets(url: url, body: body, headerValues: values)
        return (pub, secrets)
    }

    /// Reassemble a full config from its persisted halves. Secrets may be
    /// `nil` when the slot has never been configured or when reads fail
    /// gracefully (per spec: missing Keychain items return `nil`, never
    /// throw at this layer).
    static func assemble(public pub: CustomActionPublicConfig, secrets: CustomActionSecrets?) -> CustomActionConfig {
        let values = secrets?.headerValues ?? [:]
        let headers = pub.headerNames.map { entry in
            CustomActionHeader(id: entry.id, name: entry.name, value: values[entry.id.uuidString] ?? "")
        }
        return CustomActionConfig(
            enabled: pub.enabled,
            name: pub.name,
            symbol: pub.symbol,
            method: pub.method,
            visibility: pub.visibility,
            confirmBeforeRun: pub.confirmBeforeRun,
            url: secrets?.url ?? "",
            headers: headers,
            body: secrets?.body ?? ""
        )
    }
}

/// Pure visibility resolver. Returns `false` when the slot is disabled or
/// when the visibility gate filters it out. Header slots that fail render
/// as a 32pt empty spacer so the printer-name title stays centered; row
/// slots collapse the same way as disabled (1 visible -> full width,
/// 0 visible -> row not rendered).
public func isCustomActionVisible(
    _ config: CustomActionConfig,
    isDisconnected: Bool,
    isUnconfigured: Bool
) -> Bool {
    guard config.enabled else { return false }
    switch config.visibility {
    case .always:
        return true
    case .whenConnected:
        return !isDisconnected && !isUnconfigured
    case .whenDisconnected:
        return isDisconnected || isUnconfigured
    }
}
