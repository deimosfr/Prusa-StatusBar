import Foundation
import Network

/// Shared syntactic check for the host component of any user-entered URL or
/// host field on the Printer tab. `URL(string:)` accepts dotted-decimal
/// strings like `192.168.94.1312` even though the last octet overflows, so
/// every field that delegates to `URL(string:)` needs this extra guard.
///
/// Rules:
/// - IPv4 literal (all digits + dots): must parse via `IPv4Address`.
/// - IPv6 literal (contains `:`, with or without enclosing brackets): must
///   parse via `IPv6Address`.
/// - Anything else is treated as a DNS hostname and accepted; the caller is
///   expected to have already verified non-emptiness via `URL.host`.
public enum URLHostValidator {
    public static func isValid(host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let unbracketed: String = if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            String(trimmed.dropFirst().dropLast())
        } else {
            trimmed
        }
        if unbracketed.contains(":") {
            return IPv6Address(unbracketed) != nil
        }
        let looksLikeIPv4 = unbracketed.allSatisfy { $0.isNumber || $0 == "." }
        if looksLikeIPv4 {
            return IPv4Address(unbracketed) != nil
        }
        return true
    }
}
