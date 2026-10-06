import AppKit
import IthilCore
import SwiftUI

/// The menu bar: File › New Event… (⌘N, Quick Add) instead of New Window, and the calendar's navigation
/// in the View menu, as in Calendar.app: Today ⌘T, Day / Week / Month ⌘1–3, Previous / Next ⌘← / ⌘→.
struct IthilCommands: Commands {
    let model: AppModel
    let settings: AppSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            NewEventCommand(model: model, settings: settings)
        }
        CommandGroup(before: .toolbar) {
            CalendarNavigationCommands(model: model)
        }
        SidebarCommands()
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
