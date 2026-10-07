import Foundation
import IthilCore
import os

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "LibraryFolderChoice")

/// What choosing another folder in Settings → Files means, worked out before anything is moved.
enum LibraryFolderChoice: Equatable, Sendable {
    /// The chosen folder is (or holds, as `Ithil`) the calendar that is open now.
    case currentLibrary
    /// The chosen folder is inside the open calendar's folder.
    case insideCurrentLibrary
    /// The chosen folder is (or holds, as `Ithil`) another Ithil calendar, which can be opened instead.
    case otherLibrary(URL)
    /// The calendar can move there: into `newRoot`, the chosen folder itself when it is empty, otherwise
    /// a new or empty `Ithil` (`Ithil 2`…) folder inside it, as `RootFolderPolicy` picks.
    case move(chosen: URL, newRoot: URL)
    /// The chosen folder can't be used (gone, unreadable, or no free `Ithil N` name).
    case unavailable

    /// Decides what choosing `chosen` means while the calendar in `currentRoot` is open. Reads the disk
    /// and writes nothing: call it off the main actor.
    static func evaluate(_ chosen: URL, currentRoot: URL) -> LibraryFolderChoice {
        let fileSystem = LocalFileSystem()
        guard fileSystem.isDirectory(at: chosen) else { return .unavailable }
        if isSameFolder(chosen, currentRoot) {
            return .currentLibrary
        }
        if EventFolders(root: currentRoot, fileSystem: fileSystem).contains(chosen) {
            return .insideCurrentLibrary
        }
        if RootFolderPolicy.isIthilFolder(chosen, fileSystem: fileSystem) {
            return .otherLibrary(chosen)
        }
        if RootFolderPolicy.isEffectivelyEmpty(chosen, fileSystem: fileSystem) {
            return .move(chosen: chosen, newRoot: chosen)
        }
        // The same order as `RootFolderPolicy.libraryFolder(forChosen:fileSystem:)`.
        let baseName = RootFolderPolicy.defaultFolderName
        for number in 1...999 {
            let name = number == 1 ? baseName : "\(baseName) \(number)"
            let candidate = chosen.appending(component: name, directoryHint: .isDirectory)
            if !fileSystem.fileExists(at: candidate) {
                return .move(chosen: chosen, newRoot: candidate)
            }
            if RootFolderPolicy.isIthilFolder(candidate, fileSystem: fileSystem) {
                return isSameFolder(candidate, currentRoot) ? .currentLibrary : .otherLibrary(candidate)
            }
            if RootFolderPolicy.isEffectivelyEmpty(candidate, fileSystem: fileSystem) {
                return .move(chosen: chosen, newRoot: candidate)
            }
        }
        return .unavailable
    }

    /// Moves the calendar in `oldRoot` to where choosing `chosen` puts it, after checking again that it
    /// still can (`FilesError.folderChanged` otherwise), and returns the new root.
    ///
    /// `LibraryMove` moves Ithil's own items and nothing else, and moves everything back if a step fails.
    /// A new `Ithil` folder made for the move is removed again if the move failed and left it completely
    /// empty. Can take long across volumes: call it off the main actor, with nothing else writing to the
    /// library.
    static func moveLibrary(from oldRoot: URL, toChosen chosen: URL) throws -> URL {
        guard case .move(_, let newRoot) = evaluate(chosen, currentRoot: oldRoot) else {
            throw FilesError.folderChanged
        }
        let fileSystem = LocalFileSystem()
        let isNewFolder = !fileSystem.fileExists(at: newRoot)
        do {
            try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)
        } catch {
            if isNewFolder {
                removeIfCompletelyEmpty(newRoot)
            }
            throw error
        }
        return newRoot
    }

    /// Whether two URLs name the same folder once `.`, `..` and symbolic links are resolved.
    private static func isSameFolder(_ first: URL, _ second: URL) -> Bool {
        let firstPath = first.standardizedFileURL.resolvingSymlinksInPath().path
        let secondPath = second.standardizedFileURL.resolvingSymlinksInPath().path
        return firstPath == secondPath
    }

    /// Removes a folder only if nothing at all is in it (`rmdir` refuses anything else).
    private static func removeIfCompletelyEmpty(_ folder: URL) {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard contents?.isEmpty == true else { return }
        let removed = folder.withUnsafeFileSystemRepresentation { path in
            path.map { rmdir($0) == 0 } ?? false
        }
        if !removed {
            logger.notice("Could not remove the empty folder made for a failed move")
        }
    }
}
