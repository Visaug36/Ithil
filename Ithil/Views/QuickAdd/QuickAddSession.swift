import AppKit
import IthilCore
import Observation
import os

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "QuickAdd")

/// One opening of the Quick Add panel: the line being typed, what it means, and what Return and ⌘Return
/// do with it.
///
/// The text is parsed again on every change (cheap) with a fresh `AppModel.makeQuickAddParser()`, so the
/// subjects and the default alert are always current. Return adds the event and closes; ⌘Return also
/// shows its day in the main window and asks the calendar to open its editor
/// (`AppModel.pendingEditorOccurrenceID`). Blank text does nothing.
@Observable @MainActor
final class QuickAddSession {
    var text = ""
    private let model: AppModel
    private let onClose: () -> Void
    private let onReveal: () -> Void

    /// `onClose` hides the panel; `onReveal` hides it and brings the main window forward.
    init(model: AppModel, onClose: @escaping () -> Void, onReveal: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        self.onReveal = onReveal
    }

    /// What the text describes, or nil while it is blank.
    var draft: QuickAddDraft? {
        model.makeQuickAddParser().parse(text, now: model.now)
    }

    /// Adds the event. With `openingEditor`, the main window shows it and opens its editor.
    func submit(openingEditor: Bool) {
        let parser = model.makeQuickAddParser()
        guard let draft = parser.parse(text, now: model.now) else { return }
        guard model.canEdit else {
            NSSound.beep()
            return
        }
        let event = parser.makeEvent(from: draft, fallbackTitle: String(localized: "New Event"), now: model.now)
        model.add(event)
        logger.info("Quick Add added \(event.title, privacy: .private)")
        guard openingEditor else {
            onClose()
            return
        }
        reveal(event)
        onReveal()
    }

    func cancel() {
        onClose()
    }

    /// Makes sure the calendar can show the new event (its subject visible, no search results over it),
    /// moves to its day and asks for its editor.
    private func reveal(_ event: Event) {
        if let subjectID = event.subjectID, !model.isVisible(subjectID) {
            model.setVisible(true, subjectID: subjectID)
        }
        model.searchText = ""
        let id = Occurrence.ID(eventID: event.id, date: event.timing.startDate)
        var day = event.timing.startDate
        if let occurrence = model.occurrence(id: id) {
            day = EventFormatting.displayDay(of: occurrence, timeZone: model.timeZone)
        }
        model.show(day, span: nil)
        model.pendingEditorOccurrenceID = id
    }
}
