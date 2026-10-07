import AppKit

/// AppKit hooks SwiftUI's `App` doesn't offer.
///
/// - Before launch finishes, `NotificationDelegate.shared` becomes the notification center's delegate, so a
///   click on an alert that launched Ithil reaches `NotificationsController` (which attaches itself to the
///   delegate when it is created, and re-reads the permission whenever Ithil becomes active).
/// - Quitting waits (briefly) for the library's last save, so a change made just before ⌘Q is never lost.
///   The app sets `model` when its first window appears.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    /// How long quitting waits for a save in progress before giving up.
    private let saveTimeout: Duration = .seconds(5)

    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationDelegate.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.hasPendingSaves else { return .terminateNow }
        let timeout = saveTimeout
        Task { @MainActor in
            await model.finishPendingSaves(timeout: timeout)
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
