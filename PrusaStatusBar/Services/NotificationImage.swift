import Foundation

/// Helpers for producing a file-on-disk image suitable for
/// `UNNotificationAttachment`. macOS requires the attachment to be a real
/// file URL; raw `Data` is not accepted.
enum NotificationImage {
    /// Persist arbitrary image bytes (PNG/JPEG, whatever the printer returned)
    /// to a unique temp file. Returns nil on write failure: the caller must
    /// gracefully degrade to a no-image notification.
    static func writeTemp(data: Data, suggestedExtension: String = "png") -> URL? {
        let url = uniqueTempURL(extension: suggestedExtension)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.notifications.notice(
                "Notification temp write failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func uniqueTempURL(extension ext: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return dir.appendingPathComponent("prusa-notif-\(UUID().uuidString).\(ext)")
    }
}
