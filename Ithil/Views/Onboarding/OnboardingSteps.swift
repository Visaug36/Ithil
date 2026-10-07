import SwiftUI

/// One onboarding page, in the style of the folder screens: the app icon, a New York headline, a line of
/// explanation, then the page's own content and buttons, and optionally a footnote. Centered, at most
/// 440 pt wide. VoiceOver starts on the headline when a page appears.
struct OnboardingPage<Content: View>: View {
    private let title: Text
    private let message: Text
    private let footnote: Text?
    private let content: Content
    @AccessibilityFocusState private var isTitleFocused: Bool

    init(title: Text, message: Text, footnote: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.message = message
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 22) {
            AppIconImage(size: 96)
            header
            content
            if let footnote {
                footnote
                    .font(Typography.secondary)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
        .onAppear {
            isTitleFocused = true
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            title
                .font(Typography.monthTitle)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
            message
                .font(Typography.body)
                .foregroundStyle(Color.textSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 1. Welcome

/// "Welcome to Ithil", the one-line pitch, three points, and "Continue".
struct WelcomeStep: View {
    let onContinue: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        OnboardingPage(title: Text("Welcome to Ithil"), message: pitch) {
            WelcomePoints(quickAddShortcut: settings.quickAddHotKey?.displayString)
            Button("Continue") {
                onContinue()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var pitch: Text {
        Text("A calm calendar for your classes, with every event’s files close at hand.")
    }
}

/// The three points on a raised, radius-10 card: offline and private, files in real folders, Quick Add.
private struct WelcomePoints: View {
    /// The global Quick Add shortcut ("⌥Space"), or nil when it is off.
    let quickAddShortcut: String?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.formGroup, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            WelcomePoint(
                symbol: "lock",
                title: Text("Offline and private"),
                detail: Text("No account, no internet. Everything stays on your Mac, in a folder you choose."))
            WelcomePoint(
                symbol: "folder",
                title: Text("Files in real folders"),
                detail: Text("Each event’s files live in their own Finder folder, so you can open them anywhere."))
            WelcomePoint(symbol: "keyboard", title: quickAddTitle, detail: quickAddDetail)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.backgroundRaised))
        .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    /// The card's edge, stronger with Increase Contrast (like the folder screens' buttons).
    private var border: Color {
        contrast == .increased ? Color.textTertiary : Color.separatorLine
    }

    /// "From anywhere" only while the global shortcut is on; otherwise ⌘N works inside Ithil.
    private var quickAddTitle: Text {
        quickAddShortcut == nil ? Text("Quick Add") : Text("Quick Add from anywhere")
    }

    private var quickAddDetail: Text {
        if let quickAddShortcut {
            return Text("Press \(quickAddShortcut) in any app and type “physics quiz thursday 10am”.")
        }
        return Text("Press ⌘N and type “physics quiz thursday 10am”.")
    }
}

/// A moonlight symbol beside a 13 pt semibold title and a secondary line. Read as one sentence by VoiceOver.
private struct WelcomePoint: View {
    let symbol: String
    let title: Text
    let detail: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                detail
                    .font(Typography.secondary)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 2. Choose folder

/// The choose-folder screen's words and `ChooseFolderActions`. Choosing a folder opens the library, and
/// `MainView` moves on to the notifications page once it is ready.
struct ChooseFolderStep: View {
    private typealias Words = ChooseFolderView

    var body: some View {
        OnboardingPage(title: Words.title, message: Words.message, footnote: Words.footnote) {
            VStack(spacing: 10) {
                ChooseFolderActions()
            }
        }
    }
}

// MARK: - 3. Notifications

/// `NotificationPermissionView`, then "Skip" until macOS has an answer and "Continue" after. The card's
/// own "Not Now" (which also hides the sidebar suggestion for good) finishes too.
struct NotificationsStep: View {
    let onFinish: () -> Void
    @Environment(NotificationsController.self) private var notifications

    var body: some View {
        OnboardingPage(title: title, message: message, footnote: footnote) {
            NotificationPermissionView(onNotNow: { onFinish() })
                .frame(maxWidth: 380)
            finishButton
        }
        .task {
            await notifications.refreshAuthorization()
        }
    }

    private var title: Text {
        Text("Stay on time")
    }

    private var message: Text {
        Text("One more thing before your calendar opens.")
    }

    private var footnote: Text {
        Text("You can change this later in Settings.")
    }

    @ViewBuilder private var finishButton: some View {
        if hasAnswer {
            Button("Continue") {
                onFinish()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
        } else {
            Button("Skip") {
                onFinish()
            }
            .buttonStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Color.accentText)
            .accessibilityHint(Text("Opens your calendar without turning on notifications"))
        }
    }

    /// True once the user allowed or declined notifications.
    private var hasAnswer: Bool {
        switch notifications.authorization {
        case .authorized, .denied:
            return true
        case .notDetermined, .unknown:
            return false
        }
    }
}
