import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "LaunchAtLogin")

/// Opening Ithil at login, through `SMAppService.mainApp` (no helper app, no permission prompt).
///
/// macOS shows the result in System Settings → General → Login Items, where the user can also switch it
/// off. Then the app stays registered but `status` is `.requiresApproval` until they switch it back on
/// there; Settings explains that and offers `openLoginItemsSettings()`.
@MainActor
enum LaunchAtLogin {
    enum Status: Hashable, Sendable {
        /// Ithil opens at login.
        case on
        /// Ithil isn't registered to open at login.
        case off
        /// Registered, but switched off in System Settings → General → Login Items.
        case requiresApproval
    }

    /// What macOS says now. Cheap enough to read whenever Settings appears or Ithil becomes active.
    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            // `.notFound` is also what an app that never registered can get; registering still works.
            return .off
        @unknown default:
            return .off
        }
    }

    /// Registers or unregisters Ithil as a login item. Does nothing when it already is as asked.
    static func set(_ on: Bool) throws {
        let service = SMAppService.mainApp
        do {
            if on {
                guard service.status != .enabled else { return }
                try service.register()
            } else {
                guard service.status == .enabled || service.status == .requiresApproval else { return }
                try service.unregister()
            }
        } catch {
            let action = on ? "register" : "unregister"
            logger.error(
                "Could not \(action, privacy: .public) the login item: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Opens System Settings → General → Login Items.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
