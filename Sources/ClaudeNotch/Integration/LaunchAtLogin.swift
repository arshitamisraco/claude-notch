import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
        }
    }

    static let approvalHint = "Approve Claude Notch in System Settings > General > Login Items."
}
