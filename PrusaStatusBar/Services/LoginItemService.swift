import Foundation
import ServiceManagement

public enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case disabled
    case requiresApproval
}

/// Protocol over `SMAppService.mainApp` so the login-item spec can be tested
/// without hitting the system service.
public protocol LoginItemService: Sendable {
    func currentStatus() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) throws
}

#if !PROTOTYPE_MODE
    public struct SMAppLoginItemService: LoginItemService {
        public init() {}

        public func currentStatus() -> LoginItemStatus {
            switch SMAppService.mainApp.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                return .disabled
            @unknown default:
                return .disabled
            }
        }

        public func setEnabled(_ enabled: Bool) throws {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }
#endif

/// In-memory stub used by prototype mode and tests.
public final class StubLoginItemService: LoginItemService, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    public init(initiallyEnabled: Bool = false) {
        enabled = initiallyEnabled
    }

    public func currentStatus() -> LoginItemStatus {
        lock.lock()
        defer { lock.unlock() }
        return enabled ? .enabled : .disabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        self.enabled = enabled
    }
}
