import Foundation
import UserNotifications

/// Protocol over `UNUserNotificationCenter` so the notifications spec can be
/// tested without involving the system service. `imageURL` is an optional
/// file URL on disk that, when set, is wrapped in a `UNNotificationAttachment`
/// and shown as the banner thumbnail. The caller owns the file's lifetime;
/// the system copies it during `add(_:)`.
public protocol NotificationService: Sendable {
    func requestAuthorization() async -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func deliver(title: String, body: String, identifier: String, imageURL: URL?) async
}

public extension NotificationService {
    func deliver(title: String, body: String, identifier: String) async {
        await deliver(title: title, body: body, identifier: identifier, imageURL: nil)
    }
}

#if !PROTOTYPE_MODE
    // Production wrapper. The class is also the `UNUserNotificationCenter`
    // delegate, which is required for menu-bar `.accessory` apps to display
    // banners while the app is "active" (popover open, recently interacted
    // with). Without a delegate that returns presentation options from
    // `willPresent`, macOS silently swallows the notification.
    // swiftlint:disable:next line_length
    public final class UNNotificationService: NSObject, NotificationService, UNUserNotificationCenterDelegate, @unchecked Sendable {
        override public init() {
            super.init()
            UNUserNotificationCenter.current().delegate = self
        }

        public func requestAuthorization() async -> Bool {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Log.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }

        public func authorizationStatus() async -> UNAuthorizationStatus {
            await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    continuation.resume(returning: settings.authorizationStatus)
                }
            }
        }

        public func deliver(title: String, body: String, identifier: String, imageURL: URL?) async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let imageURL, let attachment = makeAttachment(identifier: identifier, url: imageURL) {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                Log.notifications.info(
                    "Delivered notification \(identifier, privacy: .public): \(title, privacy: .public)"
                )
            } catch {
                Log.notifications.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        public func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .list, .sound])
        }

        /// Best-effort attachment build. A failure here (file moved between
        /// generation and delivery, unsupported MIME) MUST NOT cancel the
        /// notification; we just drop the image and let the alert through.
        private func makeAttachment(identifier: String, url: URL) -> UNNotificationAttachment? {
            do {
                return try UNNotificationAttachment(identifier: "\(identifier).image", url: url, options: nil)
            } catch {
                let file = url.lastPathComponent
                let detail = error.localizedDescription
                Log.notifications.notice(
                    "Attachment build failed (\(file, privacy: .public)): \(detail, privacy: .public)"
                )
                return nil
            }
        }
    }
#endif

/// Stub used by prototype mode and tests.
public final class StubNotificationService: NotificationService, @unchecked Sendable {
    public struct DeliveredNotification: Equatable, Sendable {
        public let title: String
        public let body: String
        public let identifier: String
        public let imageURL: URL?
    }

    public private(set) var delivered: [DeliveredNotification] = []
    public var grantAuthorization: Bool = true

    public init() {}

    public func requestAuthorization() async -> Bool {
        grantAuthorization
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        grantAuthorization ? .authorized : .denied
    }

    public func deliver(title: String, body: String, identifier: String, imageURL: URL?) async {
        delivered.append(DeliveredNotification(
            title: title,
            body: body,
            identifier: identifier,
            imageURL: imageURL
        ))
    }
}
