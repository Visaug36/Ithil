import AppKit
import Foundation
import IthilCore
import os

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "FolderAccess")

/// The library folder Ithil remembers between launches: a security-scoped bookmark, the path it had when
/// it was last opened (to show when the bookmark no longer resolves), and the ID of the library found
/// there (so `LibraryStore` can find its safety copy if events.json is damaged).
///
/// Never read or written in `-demo` mode.
struct SavedFolder: Equatable, Sendable {
    var bookmark: Data
    var path: String
    var libraryID: UUID?

    static func load(from defaults: UserDefaults) -> SavedFolder? {
        guard let bookmark = defaults.data(forKey: Key.bookmark) else { return nil }
        let path = defaults.string(forKey: Key.path) ?? ""
        let libraryID = defaults.string(forKey: Key.libraryID).flatMap { UUID(uuidString: $0) }
        return SavedFolder(bookmark: bookmark, path: path, libraryID: libraryID)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(bookmark, forKey: Key.bookmark)
        defaults.set(path, forKey: Key.path)
        if let libraryID {
            defaults.set(libraryID.uuidString, forKey: Key.libraryID)
        } else {
            defaults.removeObject(forKey: Key.libraryID)
        }
    }

    private enum Key {
        static let bookmark = "libraryFolderBookmark"
        static let path = "libraryFolderPath"
        static let libraryID = "libraryFolderLibraryID"
    }
}

/// Security-scoped bookmarks, the folder panels, and the small bits of disk work around choosing and
/// opening a library folder.
///
/// Everything except the panels is plain synchronous code meant to run off the main thread (in a
/// detached task); the panels are `@MainActor`.
enum FolderAccess {
    // MARK: - Bookmarks

    enum Resolution: Sendable {
        /// The folder is there. Its security scope has been entered when `isAccessing` is true; a stale
        /// bookmark comes with a fresh one to save.
        case available(URL, refreshedBookmark: Data?, isAccessing: Bool)
        /// The bookmark resolves, but not to a folder (deleted, or moved to the Trash).
        case missing
        /// The bookmark no longer resolves (folder gone, drive unplugged, bookmark damaged).
        case unresolvable
    }

    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a saved bookmark and enters its security scope. A bookmark of a folder that was moved or
    /// renamed resolves to its new place (and is stale, so it gets refreshed); one that now points into
    /// the Trash counts as missing, so Ithil never keeps working in a deleted folder.
    static func resolve(_ bookmark: Data) -> Resolution {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        } catch {
            let reason = String(describing: error)
            logger.error("The folder bookmark doesn't resolve: \(reason, privacy: .private)")
            return .unresolvable
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        guard LocalFileSystem().isDirectory(at: url), !isInTrash(url) else {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            logger.error("The library folder is missing")
            return .missing
        }
        var refreshed: Data?
        if isStale {
            do {
                refreshed = try makeBookmark(for: url)
            } catch {
                let reason = String(describing: error)
                logger.error("Could not refresh a stale folder bookmark: \(reason, privacy: .private)")
            }
        }
        return .available(url, refreshedBookmark: refreshed, isAccessing: isAccessing)
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    // MARK: - Choosing a folder

    /// A folder the user chose, turned into a library root.
    struct PreparedFolder: Sendable {
        var root: URL
        /// The root already has a `.ithil` folder, so it is loaded rather than created.
        var hasLibrary: Bool
        /// A security-scoped bookmark of `root`, to open it again at the next launch.
        var bookmark: Data
    }

    enum SetupError: Error {
        /// "Locate Folder…" was pointed at a folder that holds no Ithil calendar.
        case noCalendarFound
    }

    /// Turns the folder the user chose into a library root.
    ///
    /// - Choosing (`relocating == false`): a folder that doesn't exist yet (from "Create Ithil Folder…") is
    ///   created, then `RootFolderPolicy` picks the folder itself (empty or already Ithil's) or an `Ithil`
    ///   subfolder inside it.
    /// - Relocating ("Locate Folder…"): the folder must be an Ithil folder, or contain one named `Ithil`;
    ///   anything else throws `noCalendarFound`, so a missing calendar is never replaced by an empty one.
    static func prepare(_ chosen: URL, relocating: Bool) throws -> PreparedFolder {
        let fileSystem = LocalFileSystem()
        let root: URL
        if relocating {
            root = try existingLibraryFolder(in: chosen, fileSystem: fileSystem)
        } else {
            if !fileSystem.fileExists(at: chosen) {
                try fileSystem.createDirectory(at: chosen)
            }
            root = try RootFolderPolicy.libraryFolder(forChosen: chosen, fileSystem: fileSystem)
        }
        let hasLibrary = RootFolderPolicy.isIthilFolder(root, fileSystem: fileSystem)
        let bookmark = try makeBookmark(for: root)
        return PreparedFolder(root: root, hasLibrary: hasLibrary, bookmark: bookmark)
    }

    private static func existingLibraryFolder(in chosen: URL, fileSystem: any FileSystem) throws -> URL {
        if RootFolderPolicy.isIthilFolder(chosen, fileSystem: fileSystem) {
            return chosen
        }
        let child = chosen.appending(component: RootFolderPolicy.defaultFolderName, directoryHint: .isDirectory)
        if RootFolderPolicy.isIthilFolder(child, fileSystem: fileSystem) {
            return child
        }
        throw SetupError.noCalendarFound
    }

    static func folderExists(at url: URL) -> Bool {
        LocalFileSystem().isDirectory(at: url)
    }

    /// Creates Application Support/Ithil/SafetyCopies (or the demo's own) if needed. Failures are only
    /// logged: `LibraryStore` tries again whenever it writes a safety copy.
    static func prepareSafetyDirectory(_ url: URL) {
        do {
            try LocalFileSystem().createDirectory(at: url)
        } catch {
            let reason = String(describing: error)
            logger.error("Could not create the safety copy folder: \(reason, privacy: .private)")
        }
    }

    // MARK: - Demo

    struct DemoFolders: Sendable {
        var root: URL
        var safetyCopies: URL
    }

    /// A fresh temporary folder for `-demo`: `<tmp>/Ithil Demo <UUID>/Ithil` plus its own safety copy
    /// folder beside it, so demo runs never touch the user's data or Application Support.
    static func makeDemoFolders() throws -> DemoFolders {
        let base = URL.temporaryDirectory.appending(
            component: "Ithil Demo \(UUID().uuidString)", directoryHint: .isDirectory)
        let folders = DemoFolders(
            root: base.appending(component: RootFolderPolicy.defaultFolderName, directoryHint: .isDirectory),
            safetyCopies: base.appending(component: "SafetyCopies", directoryHint: .isDirectory))
        let fileSystem = LocalFileSystem()
        try fileSystem.createDirectory(at: folders.root)
        try fileSystem.createDirectory(at: folders.safetyCopies)
        return folders
    }

    // MARK: - Newer libraries

    /// Reads events.json from a newer Ithil as far as this version understands it, to show it read-only.
    /// Nil when it doesn't decode, or decodes to nothing (a format change could otherwise look like an
    /// empty calendar).
    static func readLibraryFromNewerVersion(at root: URL) -> Library? {
        let file = root.appending(components: ".ithil", "events.json", directoryHint: .notDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? LocalFileSystem().readData(at: file),
            let library = try? decoder.decode(Library.self, from: data),
            !library.events.isEmpty || !library.subjects.isEmpty
        else { return nil }
        return library
    }

    // MARK: - Paths

    /// The user's real home folder (not the sandbox container's).
    static var userHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
        }
        return URL.homeDirectory
    }

    /// ~/Documents, where Ithil suggests its folder.
    static var documentsFolder: URL {
        userHome.appending(component: "Documents", directoryHint: .isDirectory)
    }

    /// "~/Documents/Ithil".
    static var suggestedFolderDisplayPath: String {
        let suggested = documentsFolder.appending(
            component: RootFolderPolicy.defaultFolderName, directoryHint: .isDirectory)
        return displayPath(suggested.path)
    }

    /// `path` with the home folder shown as "~".
    static func displayPath(_ path: String) -> String {
        let home = userHome.path
        guard home.count > 1, path == home || path.hasPrefix(home + "/") else { return path }
        return "~\(path.dropFirst(home.count))"
    }

    // MARK: - Panels

    /// Asks where to create the Ithil folder, suggesting ~/Documents/Ithil. Returns the chosen URL; the
    /// folder itself is created by `prepare(_:relocating:)`.
    @MainActor
    static func createFolder() -> URL? {
        let panel = NSSavePanel()
        panel.title = String(localized: "Create Your Ithil Folder")
        panel.message = String(localized: "Ithil keeps your calendar and every event's files in this folder.")
        panel.prompt = String(localized: "Create")
        panel.nameFieldLabel = String(localized: "Folder name:")
        panel.nameFieldStringValue = RootFolderPolicy.defaultFolderName
        panel.canCreateDirectories = true
        panel.directoryURL = documentsFolder
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Asks for an existing folder to keep the calendar in.
    @MainActor
    static func chooseExistingFolder() -> URL? {
        chooseFolder(
            title: String(localized: "Choose a Folder for Ithil"),
            message: String(localized: "Choose an Ithil folder, or a folder to create one in."),
            startingAt: documentsFolder)
    }

    /// Asks where the missing Ithil folder went, starting next to where it used to be.
    @MainActor
    static func locateFolder(lastKnownPath: String) -> URL? {
        var start = documentsFolder
        if !lastKnownPath.isEmpty {
            start = URL(filePath: lastKnownPath, directoryHint: .isDirectory).deletingLastPathComponent()
        }
        return chooseFolder(
            title: String(localized: "Locate Your Ithil Folder"),
            message: String(localized: "Choose the folder that has your Ithil calendar in it."),
            startingAt: start)
    }

    @MainActor
    private static func chooseFolder(title: String, message: String, startingAt directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = String(localized: "Use This Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
