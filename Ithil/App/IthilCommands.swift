import AppKit
import IthilCore
import SwiftUI

/// The menu bar: Ithil › About Ithil (Ithil's own About window); File › New Event… (⌘N, Quick Add) instead
/// of New Window; Edit › Find… (⌘F, the calendar's search field); the calendar's navigation in the View
/// menu, as in Calendar.app: Today ⌘T, Day / Week / Month ⌘1–3, Previous / Next ⌘← / ⌘→; and a Help menu
/// that opens the project's GitHub pages in the browser (Ithil itself never goes online).
struct IthilCommands: Commands {
    let model: AppModel
    let settings: AppSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            AboutCommand()
        }
        CommandGroup(replacing: .newItem) {
            NewEventCommand(model: model, settings: settings)
        }
        // Before the system's Find submenu, so ⌘F always reaches `FindCommand` first, whatever the system
        // item's enabled state; `FindCommand` hands it on to a text view that can find.
        CommandGroup(before: .textEditing) {
            FindCommand(model: model)
        }
        CommandGroup(before: .toolbar) {
            CalendarNavigationCommands(model: model)
        }
        CommandGroup(replacing: .help) {
            HelpCommands()
        }
        SidebarCommands()
    }
}

/// Ithil › About Ithil: the About window (`AboutView`), brought forward if it is already open.
private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Ithil") {
            openWindow(id: AboutView.windowID)
        }
    }
}

/// Menu items are views, so their enabled state follows the model through Observation.
private struct NewEventCommand: View {
    let model: AppModel
    let settings: AppSettings

    var body: some View {
        Button("New Event…") {
            QuickAddPanelController.shared.show(model: model, settings: settings)
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(!model.canEdit)
    }
}

/// Edit › Find… ⌘F focuses the calendar's search field (`SearchFocus`).
///
/// While a text view is being edited (the notes in the editor, a text field), ⌘F belongs to that text, as in
/// any Mac app: this item passes the request on to the text's own find bar when it has one (what the
/// system's Find item would do), and beeps when it has none. In the search field itself it just keeps the
/// field focused.
private struct FindCommand: View {
    let model: AppModel

    var body: some View {
        Button("Find…") {
            find()
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(model.state != .ready)
    }

    private func find() {
        guard let textView = NSApplication.shared.keyWindow?.firstResponder as? NSTextView else {
            SearchFocus.focus()
            return
        }
        if textView.isFieldEditor, textView.delegate is NSSearchField {
            SearchFocus.focus()
            return
        }
        guard textView.usesFindBar || textView.usesFindPanel else {
            NSSound.beep()
            return
        }
        let request = NSMenuItem()
        request.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(request)
    }
}

/// The Help menu: the project's pages on GitHub, opened in the browser.
private struct HelpCommands: View {
    var body: some View {
        Button("Ithil on GitHub") {
            AppLinks.open(AppLinks.repository)
        }
        Divider()
        Button("Check for Updates…") {
            AppLinks.open(AppLinks.releases)
        }
        Button("Report an Issue…") {
            AppLinks.open(AppLinks.newIssue)
        }
    }
}

private struct CalendarNavigationCommands: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Today") {
                model.goToToday()
            }
            .keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Day") {
                model.span = .day
            }
            .keyboardShortcut("1", modifiers: .command)
            Button("Week") {
                model.span = .week
            }
            .keyboardShortcut("2", modifiers: .command)
            Button("Month") {
                model.span = .month
            }
            .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button(previousTitle) {
                goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            Button(nextTitle) {
                goForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            Divider()
        }
        .disabled(model.state != .ready)
    }

    private var previousTitle: LocalizedStringKey {
        switch model.span {
        case .day: "Previous Day"
        case .week: "Previous Week"
        case .month: "Previous Month"
        }
    }

    private var nextTitle: LocalizedStringKey {
        switch model.span {
        case .day: "Next Day"
        case .week: "Next Week"
        case .month: "Next Month"
        }
    }

    /// ⌘← / ⌘→ belong to the text while typing (search field, editor, Quick Add): there they move to
    /// the start or end of the line as usual, and only elsewhere step the calendar.
    private func goBack() {
        if let textView = editingTextView() {
            textView.moveToLeftEndOfLine(nil)
        } else {
            model.step(-1)
        }
    }

    private func goForward() {
        if let textView = editingTextView() {
            textView.moveToRightEndOfLine(nil)
        } else {
            model.step(1)
        }
    }

    private func editingTextView() -> NSTextView? {
        NSApplication.shared.keyWindow?.firstResponder as? NSTextView
    }
}
