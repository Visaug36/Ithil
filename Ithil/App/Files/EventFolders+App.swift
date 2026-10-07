import Foundation
import IthilCore

/// What a batch of folder changes did.
struct EventFolderWorkReport: Sendable {
    /// How many folders were renamed, moved or put in the Trash.
    var changed = 0
    var failures: [EventFolderFailure] = []
}

/// One folder change that failed.
struct EventFolderFailure: Sendable {
    /// The event's title, for the message.
    var title: String
    var error: any Error
}

/// The app's batch operations on event folders. Each runs in one turn on the actor, so nothing else can
/// change the index halfway through.
extension EventFolders {
    /// How many items are in each occurrence's folder (0 when it has none). Never creates a folder.
    func fileCounts(for occurrences: [Occurrence]) -> [Occurrence.ID: Int] {
        var counts: [Occurrence.ID: Int] = [:]
        for occurrence in occurrences {
            counts[occurrence.id] = fileCount(for: occurrence)
        }
        return counts
    }

    /// Where Finder should go for an occurrence: its folder; else its day folder, if that exists; else
    /// the root.
    func finderTarget(for occurrence: Occurrence) -> URL {
        if let folder = existingFolder(for: occurrence) {
            return folder
        }
        let day = root.appending(component: FolderNaming.dayFolderName(for: occurrence), directoryHint: .isDirectory)
        if LocalFileSystem().isDirectory(at: day), contains(day) {
            return day
        }
        return root
    }

    /// Renames and moves the edited event's folders to match the edit (`FolderCarryPlan.moves`). A folder
    /// that can't be moved stays where it is; the others still move.
    func carryFolders(_ update: FolderUpdate) -> EventFolderWorkReport {
        let markedIDs = markedOccurrenceIDs(concerning: update.occurrence, scope: update.scope, in: update.old)
        var report = EventFolderWorkReport()
        for move in FolderCarryPlan.moves(forMarked: markedIDs, update: update) {
            do {
                if try relocate(from: move.from, to: move.to) != nil {
                    report.changed += 1
                }
            } catch {
                report.failures.append(EventFolderFailure(title: move.from.event.title, error: error))
            }
        }
        return report
    }

    /// Puts the folders of the deleted occurrences in the Trash (`FolderCarryPlan.trashTargets`); never
    /// deletes anything.
    func trashFolders(_ deletion: FolderDeletion) -> EventFolderWorkReport {
        let markedIDs = markedOccurrenceIDs(concerning: deletion.occurrence, scope: deletion.scope, in: deletion.old)
        var report = EventFolderWorkReport()
        for target in FolderCarryPlan.trashTargets(forMarked: markedIDs, deletion: deletion) {
            guard existingFolder(for: target) != nil else { continue }
            do {
                try trashFolder(for: target)
                report.changed += 1
            } catch {
                report.failures.append(EventFolderFailure(title: target.event.title, error: error))
            }
        }
        return report
    }

    /// The occurrences with marked folders that a change of `occurrence` can concern: for "all future
    /// events" of a repeating event every marked folder in the root (after a full rescan), otherwise just
    /// the occurrence's own.
    private func markedOccurrenceIDs(
        concerning occurrence: Occurrence,
        scope: SeriesEditing.Scope,
        in library: Library
    ) -> [Occurrence.ID] {
        guard scope == .allFutureEvents, FolderCarryPlan.concernsSeries(occurrence, in: library) else {
            return [occurrence.id]
        }
        return Array(markedFolders().keys)
    }
}
