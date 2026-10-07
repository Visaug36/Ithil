import AppKit
import Foundation

/// The project's pages on GitHub, for the About window and the Help menu.
///
/// They open in the user's browser with `NSWorkspace`. Ithil itself never makes a network request (it has
/// no network entitlement); handing a link to the browser is the browser's business.
enum AppLinks {
    /// https://github.com/Visaug36/Ithil
    static let repository = URL(string: "https://github.com/Visaug36/Ithil")!
    /// The newest release, where "Check for Updates…" sends the user.
    static let releases = URL(string: "https://github.com/Visaug36/Ithil/releases/latest")!
    /// The issue template chooser (bug report or feature request).
    static let newIssue = URL(string: "https://github.com/Visaug36/Ithil/issues/new/choose")!
    /// The MIT license text.
    static let license = URL(string: "https://github.com/Visaug36/Ithil/blob/main/LICENSE")!

    /// "github.com/Visaug36/Ithil", the repository as the About window shows it.
    static let repositoryDisplayName = "github.com/Visaug36/Ithil"

    /// Opens `url` in the default browser.
    @MainActor
    static func open(_ url: URL) {
        _ = NSWorkspace.shared.open(url)
    }
}
