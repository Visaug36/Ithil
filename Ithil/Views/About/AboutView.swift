import AppKit
import SwiftUI

/// The About window, in the style of the empty states: the app icon, "Ithil" in New York, the version and
/// build, links to the license and the repository, and where the name comes from, on the starry window
/// background. Opened from Ithil › About Ithil with `openWindow(id: AboutView.windowID)`.
///
/// The links open in the browser; Ithil itself never goes online.
struct AboutView: View {
    /// The About window's scene ID.
    static let windowID = "about"

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Ithil", comment: "The app's name")
                    .font(Typography.monthTitle)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: AboutInfo.versionText)
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 18) {
                AboutLink(destination: AppLinks.license) {
                    Text("MIT License")
                }
                AboutLink(destination: AppLinks.repository) {
                    Text(verbatim: AppLinks.repositoryDisplayName)
                }
            }
            Text("“Ithil” is Tolkien’s Sindarin word for the moon. Not affiliated with the Tolkien Estate.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 360)
        .starryBackground(.backgroundWindow)
    }
}

/// A link in `AccentText`, which keeps AA contrast on the window background in both themes.
private struct AboutLink<Title: View>: View {
    let destination: URL
    @ViewBuilder let title: Title

    var body: some View {
        Link(destination: destination) {
            title
                .font(Typography.secondary)
                .foregroundStyle(Color.accentText)
        }
        .accessibilityHint(Text("Opens in your browser"))
    }
}

/// The version and build from the app's Info.plist.
private enum AboutInfo {
    /// "Version 1.0.0 (1)".
    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(version) (\(build))", comment: "About window: the version and build")
    }
}

#Preview {
    AboutView()
}
