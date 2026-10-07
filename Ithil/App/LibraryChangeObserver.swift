import Foundation
import IthilCore

/// Why the library changed, for the parts of the app that keep other things in step with it: scheduled
/// alerts and event folders.
enum LibraryChange {
    /// A library was opened: at launch, after choosing or locating a folder, or after a recovery. Observers
    /// refresh what they show, but must never change anything on disk in response.
    case opened(root: URL)
    /// The user added an event.
    case added(Event)
    /// The user edited an occurrence. `old` in the callback is the library before the edit.
    case updated(Occurrence, edited: Event, scope: SeriesEditing.Scope)
    /// The user deleted an occurrence (or, with `.allFutureEvents`, the rest of its series).
    case deleted(Occurrence, scope: SeriesEditing.Scope)
    /// Subjects were added, edited or deleted.
    case subjectsChanged
    /// Undo or Redo put back an earlier version of the library (`AppModel.restore`). `old` in the callback
    /// is the library before, `new` the version put back. Observers bring what they keep in step back in
    /// line; nothing is ever moved to the Trash in response.
    case restored
}

/// Something that reacts to library changes. `AppModel` holds observers weakly and calls them on the main
/// actor right after it has updated `library`.
@MainActor
protocol LibraryChangeObserver: AnyObject {
    func libraryDidChange(_ change: LibraryChange, from old: Library, to new: Library)
}

/// A weak reference to an observer, so `AppModel` never keeps one alive.
struct WeakLibraryChangeObserver {
    weak var observer: (any LibraryChangeObserver)?
}
