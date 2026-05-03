import Foundation
import OSLog

/// Centralised loggers for the app. One subsystem (the bundle id), one category
/// per concern. The subsystem is read at runtime so the same code works in tests
/// (test bundle id) and in the shipped app.
enum Log {
    private static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.deimosfr.prusastatusbar"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let polling = Logger(subsystem: subsystem, category: "polling")
    static let menuBar = Logger(subsystem: subsystem, category: "menu-bar")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let loginItem = Logger(subsystem: subsystem, category: "login-item")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let cameraSnapshot = Logger(subsystem: subsystem, category: "camera-snapshot")
}
