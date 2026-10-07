import AppKit
import IthilCore
import SwiftUI

/// The menu bar extra's window (`MenuBarExtra` with `.menuBarExtraStyle(.window)`), as in docs/DESIGN.md
/// screen 8: today's weekday and date, a card for the next event with "Open Files", what's on today and
/// tomorrow, then menu-style rows for Quick Add, opening Ithil, Settings and Quit.
///
/// Clicking an event shows it in the main window, selected. Every action moves the keyboard to another
/// window or app, and the menu bar extra's window closes when it stops being key, so nothing has to close
/// it by hand. Until a library is open, a sentence says what Ithil is waiting for instead of the agenda.
struct MenuBarContent: View {
    /// The window's width.
    static let width: CGFloat = 300

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                MenuBarHeader()
                content
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Rectangle()
                .fill(Color.separatorLine)
                .frame(height: 1)
                .padding(.horizontal, 14)
                .accessibilityHidden(true)
            MenuBarActions()
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .frame(width: Self.width)
        .background {
            // Opaque on every macOS version, so the tokens keep the contrast docs/DESIGN.md measures. The
            // window around it (shape, edge, shadow) is drawn by the system, as Liquid Glass on macOS 26.
            Color.backgroundRaised
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .ready:
            MenuBarAgenda()
        case .loading:
            MenuBarStatusMessage(text: "Opening your calendar…")
        case .needsFolder:
            MenuBarStatusMessage(text: "Open Ithil and choose a folder for your calendar to get started.")
        case .folderMissing:
            MenuBarStatusMessage(text: "Ithil can't find its folder. Open Ithil to locate it.")
        case .noLibrary, .unreadable:
            MenuBarStatusMessage(text: "Ithil can't open your calendar. Open Ithil to see why.")
        }
    }
}

/// "Tuesday 6 October": the weekday in New York, the date in `TextSecondary`.
private struct MenuBarHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.today
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verbatim: MenuBarFormatting.weekday(today))
                .font(Typography.dayHeader)
                .foregroundStyle(Color.textPrimary)
            Text(verbatim: MenuBarFormatting.dayAndMonth(today))
                .font(Typography.body)
                .foregroundStyle(Color.textSecondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What Ithil is waiting for while no library is open.
private struct MenuBarStatusMessage: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(Typography.secondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

/// The menu-style rows at the bottom: "Quick Add… ⌥Space", "Open Ithil ⌘O", "Settings… ⌘," and
/// "Quit Ithil ⌘Q". The shortcuts work while this window is key; Quick Add's is the global one from
/// Settings (none when it is off).
private struct MenuBarActions: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            MenuBarActionRow(title: "Quick Add…", shortcut: settings.quickAddHotKey?.displayString) {
                QuickAddPanelController.shared.show(model: model, settings: settings)
            }
            .disabled(!model.canEdit)
            MenuBarActionRow(title: "Open Ithil", shortcut: "⌘O") {
                MenuBarNavigation.openIthil(openWindow: openWindow)
            }
            .keyboardShortcut("o", modifiers: .command)
            MenuBarActionRow(title: "Settings…", shortcut: "⌘,") {
                NSApplication.shared.activate()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuBarActionRow(title: "Quit Ithil", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// One menu-style row: the title on the left, its shortcut in `TextTertiary` on the right.
private struct MenuBarActionRow: View {
    let title: LocalizedStringKey
    /// Key symbols, not localized: "⌘O".
    let shortcut: String?
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            MenuBarActionLabel(title: title, shortcut: shortcut)
        }
        .buttonStyle(MenuBarRowButtonStyle())
    }
}

private struct MenuBarActionLabel: View {
    @Environment(\.isMenuBarRowHighlighted) private var isHighlighted
    let title: LocalizedStringKey
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            if let shortcut {
                Text(verbatim: shortcut)
                    .font(Typography.body)
                    .foregroundStyle(isHighlighted ? Color.textSecondary : Color.textTertiary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The menu bar icon: the `moon.fill` crescent as a template image, so it takes the menu bar's own
/// colors. VoiceOver calls it "Ithil".
struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "moon.fill")
            .renderingMode(.template)
            .accessibilityLabel(Text("Ithil", comment: "The app's name"))
    }
}

#Preview {
    MenuBarContent()
        .environment(AppModel.preview)
        .environment(AppSettings.preview)
        .environment(FilesController.preview)
        .environment(NotificationsController.preview)
}
