import Foundation
import ServiceManagement
import os

/// Thin wrapper around SMAppService for registering/unregistering the app as a
/// login item on macOS 13+. All calls are safe to make from the main actor.
@MainActor
final class LaunchAtLogin: ObservableObject {
    private let logger = Logger(subsystem: "audio.ether.app", category: "LaunchAtLogin")

    @Published var isEnabled: Bool = false
    @Published var statusDescription: String = ""

    init() { refresh() }

    /// Query the system and update `isEnabled` + `statusDescription`.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        statusDescription = description(for: status)
    }

    /// Toggle registration. Returns true if the final state matches `enable`.
    @discardableResult
    func setEnabled(_ enable: Bool) -> Bool {
        do {
            if enable {
                try SMAppService.mainApp.register()
                logger.log("Registered for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                logger.log("Unregistered from launch at login")
            }
            refresh()
            return isEnabled == enable
        } catch {
            logger.error("Launch-at-login change failed: \(error.localizedDescription, privacy: .public)")
            refresh()
            return false
        }
    }

    private func description(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:              return "Enabled"
        case .requiresApproval:     return "Requires approval in System Settings"
        case .notFound:              return "Not registered"
        case .notRegistered:         return "Not registered"
        @unknown default:           return "Unknown"
        }
    }
}
