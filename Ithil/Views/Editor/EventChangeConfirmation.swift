import IthilCore
import SwiftUI

/// What the confirmation dialog says about the event being changed or deleted.
struct EventChangeContext: Equatable {
    /// The event's title, as the question quotes it.
    var title: String
    /// A repeating event asks "This Event Only" / "All Future Events".
    var repeats: Bool
    /// "Tuesday, 6 October · 14:00 – 15:30", shown when deleting an event that doesn't repeat.
    var dayAndTime: String
}

extension EventChangeContext {
    /// The context for one occurrence, with its title, and its day and time in `timeZone`.
    init(occurrence: Occurrence, timeZone: TimeZone) {
        self.init(
            title: EventFormatting.displayTitle(occurrence.event), repeats: occurrence.event.repeats,
            dayAndTime: EventFormatting.dayAndTime(occurrence, timeZone: timeZone))
    }
}

/// The two questions the editor and the details popover ask before touching the library.
enum EventChangeAction: Hashable {
    /// Saving edits to an occurrence of a repeating event.
    case save
    /// Deleting an event (or some of a repeating event's occurrences).
    case delete
}

extension View {
    /// Asks before saving or deleting: "This Event Only" / "All Future Events" for a repeating event, or
    /// "Delete Event" for one that doesn't repeat. `perform` gets the chosen scope (`.thisEvent` for an
    /// event that doesn't repeat).
    func confirmsEventChange(
        _ action: EventChangeAction,
        isPresented: Binding<Bool>,
        context: EventChangeContext,
        perform: @escaping @MainActor (SeriesEditing.Scope) -> Void
    ) -> some View {
        modifier(EventChangeConfirmation(action: action, isPresented: isPresented, context: context, perform: perform))
    }
}

private struct EventChangeConfirmation: ViewModifier {
    let action: EventChangeAction
    @Binding var isPresented: Bool
    let context: EventChangeContext
    let perform: @MainActor (SeriesEditing.Scope) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            buttons
        } message: {
            message
        }
    }

    private var title: Text {
        switch action {
        case .save:
            return Text("Save changes to “\(context.title)”?")
        case .delete:
            return Text("Delete “\(context.title)”?")
        }
    }

    private var message: Text {
        switch action {
        case .save:
            return Text("This is a repeating event. Change only this event, or this and all future events?")
        case .delete where context.repeats:
            return Text("This is a repeating event. Delete only this event, or this and all future events?")
        case .delete:
            return Text(verbatim: context.dayAndTime)
        }
    }

    @ViewBuilder private var buttons: some View {
        let role: ButtonRole? = action == .delete ? .destructive : nil
        if context.repeats {
            Button("This Event Only", role: role) {
                perform(.thisEvent)
            }
            Button("All Future Events", role: role) {
                perform(.allFutureEvents)
            }
        } else if action == .delete {
            Button("Delete Event", role: .destructive) {
                perform(.thisEvent)
            }
        }
        Button("Cancel", role: .cancel) {}
    }
}
