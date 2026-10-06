import Foundation
import os

/// Moves a library to another folder, for changing the folder in Settings.
public enum LibraryMove {
    private static var logger: Logger {
        Logger(subsystem: "io.github.visaug36.Ithil", category: "LibraryMove")
    }

    /// Moves Ithil's own items (`.ithil` and every `yyyy-MM-dd` day folder) from `oldRoot` into
    /// `newRoot`; other files in `oldRoot` stay where they are. On the same volume the moves are renames
    /// (`FileManager.moveItem`, through `fileSystem`); across volumes each item is copied and then
    /// removed from the old place by `moveItem`. Nothing is deleted.
    ///
    /// `newRoot` must be a folder with nothing in it but Finder metadata
    /// (`RootFolderPolicy.isEffectivelyEmpty`), or not exist yet (it is then created, with its parents).
    /// Throws, moving nothing, when `oldRoot` isn't a folder (`CocoaError.fileNoSuchFile`), when
    /// `newRoot` has anything else in it or is a file (`CocoaError.fileWriteFileExists`), or when it is
    /// one of the items to move or inside one (`CocoaError.fileWriteInvalidFileName`).
    ///
    /// Day folders move first, by name, and `.ithil` last, so events.json stays in the old folder until
    /// everything else has moved. If a move fails, the items already moved are moved back (and a
    /// half-copied item left by a failed move across volumes goes to the Trash, the original being
    /// still in place), then the error is thrown. Runs on the caller's thread and can take long across
    /// volumes, so call it off the main actor, with nothing else saving or copying into the library.
    public static func move(from oldRoot: URL, to newRoot: URL, fileSystem: any FileSystem) throws {
        let oldRoot = oldRoot.standardizedFileURL
        let newRoot = newRoot.standardizedFileURL
        guard fileSystem.isDirectory(at: oldRoot) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: oldRoot])
        }
        let items = try ithilItems(in: oldRoot, fileSystem: fileSystem)
        guard !items.contains(where: { FileImportPathCheck.isInside(newRoot, root: $0) }) else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSURLErrorKey: newRoot])
        }
        if fileSystem.fileExists(at: newRoot) || FileImportSizing.anythingExists(at: newRoot) {
            guard RootFolderPolicy.isEffectivelyEmpty(newRoot, fileSystem: fileSystem) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: newRoot])
            }
        } else {
            try fileSystem.createDirectory(at: newRoot)
        }

        var moved: [LibraryMoveStep] = []
        for item in items {
            let destination = newRoot.appending(component: item.lastPathComponent, directoryHint: .isDirectory)
            let step = LibraryMoveStep(source: item, destination: destination)
            do {
                guard !FileImportSizing.anythingExists(at: step.destination) else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: step.destination])
                }
                do {
                    try fileSystem.moveItem(at: step.source, to: step.destination)
                } catch {
                    // Something that appeared at the destination in the meantime isn't a partial copy.
                    if !isDestinationTaken(error) {
                        putPartialCopyInTrash(after: step, fileSystem: fileSystem)
                    }
                    throw error
                }
                moved.append(step)
            } catch {
                let reason = String(describing: error)
                logger.error("Could not move the library: \(reason, privacy: .private)")
                moveBack(moved, fileSystem: fileSystem)
                throw error
            }
        }
        logger.notice("Moved the library (\(items.count, privacy: .public) items)")
    }

    /// The day folders in `root` sorted by name, then `.ithil`. Files with a day's name, and folders
    /// whose name isn't a real day, aren't Ithil's.
    private static func ithilItems(in root: URL, fileSystem: any FileSystem) throws -> [URL] {
        var dayFolders: [URL] = []
        var metadataFolders: [URL] = []
        for item in try fileSystem.contentsOfDirectory(at: root) where fileSystem.isDirectory(at: item) {
            let name = item.lastPathComponent
            if name == LibraryStore.metadataFolderName {
                metadataFolders.append(item)
            } else if CalendarDate(isoString: name) != nil {
                dayFolders.append(item)
            }
        }
        dayFolders.sort { $0.lastPathComponent < $1.lastPathComponent }
        return dayFolders + metadataFolders
    }

    /// After a failed move, puts what it left at the destination in the Trash, if the original is still
    /// in place: a move across volumes copies first, and a copy that failed part-way is only a partial
    /// duplicate. The destination was checked to be free before the move.
    private static func putPartialCopyInTrash(after step: LibraryMoveStep, fileSystem: any FileSystem) {
        guard fileSystem.fileExists(at: step.source), FileImportSizing.anythingExists(at: step.destination) else {
            return
        }
        do {
            try fileSystem.trashItem(at: step.destination)
        } catch {
            let reason = String(describing: error)
            logger.error("Could not put a partial copy in the Trash: \(reason, privacy: .private)")
        }
    }

    /// Whether a move failed because something was already at the destination: then what is there
    /// isn't a partial copy and must be left alone.
    private static func isDestinationTaken(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return error.code == CocoaError.Code.fileWriteFileExists.rawValue
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST)
    }

    /// Moves the items already moved back where they came from, the last one first. A failure is logged
    /// and the others are still moved back.
    private static func moveBack(_ steps: [LibraryMoveStep], fileSystem: any FileSystem) {
        for step in steps.reversed() {
            do {
                try fileSystem.moveItem(at: step.destination, to: step.source)
            } catch {
                let reason = String(describing: error)
                logger.error("Could not move an item back to the old folder: \(reason, privacy: .private)")
            }
        }
    }
}

/// One item of a library move: where it was and where it goes.
private struct LibraryMoveStep {
    var source: URL
    var destination: URL
}
