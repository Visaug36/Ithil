import Foundation
import IthilCore
import Testing

struct LibraryMoveTests {
    private let fileSystem = LocalFileSystem()

    /// Whether every file `LibraryMoveTestFolder.makeLibrary(_:)` writes is in `library`, unchanged.
    private static func expectCompleteLibrary(at library: URL) {
        for path in LibraryMoveTestFolder.libraryFiles {
            let file = library.appending(path: path, directoryHint: .notDirectory)
            let contents = try? String(contentsOf: file, encoding: .utf8)
            #expect(contents == LibraryMoveTestFolder.contents(of: file))
        }
    }

    @Test func movesIthilsItemsAndLeavesOtherFiles() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        try folder.write("Old/My notes.txt")
        let plan = try folder.write("Old/Projects/plan.md")
        try folder.write("Old/2026-13-45/not a day.txt")
        try folder.write("Old/2026-10-07.txt")
        // A file with a day's name isn't a day folder.
        try folder.write("Old/2026-10-08")
        let newRoot = folder.url.appending(path: "Elsewhere/New", directoryHint: .isDirectory)

        try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)

        let others: Set<String> = ["My notes.txt", "Projects", "2026-13-45", "2026-10-07.txt", "2026-10-08"]
        #expect(LibraryMoveTestFolder.names(in: newRoot) == [".ithil", "2026-10-06", "2026-10-14"])
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == others)
        Self.expectCompleteLibrary(at: newRoot)
        #expect(try String(contentsOf: plan, encoding: .utf8) == LibraryMoveTestFolder.contents(of: plan))
    }

    @Test func movesIntoAnEmptyFolder() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        try folder.write("New/.DS_Store")
        let newRoot = folder.url.appending(component: "New", directoryHint: .isDirectory)

        try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)

        #expect(LibraryMoveTestFolder.names(in: newRoot) == [".DS_Store", ".ithil", "2026-10-06", "2026-10-14"])
        #expect(LibraryMoveTestFolder.names(in: oldRoot).isEmpty)
        Self.expectCompleteLibrary(at: newRoot)
    }

    @Test func movesIntoAFreshFolderInsideTheOldOne() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        try folder.write("Old/My notes.txt")
        let newRoot = oldRoot.appending(component: "Calendar", directoryHint: .isDirectory)

        try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)

        #expect(LibraryMoveTestFolder.names(in: newRoot) == [".ithil", "2026-10-06", "2026-10-14"])
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == ["My notes.txt", "Calendar"])
        Self.expectCompleteLibrary(at: newRoot)
    }

    @Test func refusesAFolderThatIsNotEmpty() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        try folder.write("New/homework.pdf")
        let newRoot = folder.url.appending(component: "New", directoryHint: .isDirectory)
        let before = LibraryMoveTestFolder.names(in: oldRoot)

        #expect(throws: CocoaError.self) {
            try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)
        }
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == before)
        #expect(LibraryMoveTestFolder.names(in: newRoot) == ["homework.pdf"])
        Self.expectCompleteLibrary(at: oldRoot)
    }

    @Test func refusesAnotherLibrary() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        let newRoot = try folder.makeLibrary("Other")
        let before = LibraryMoveTestFolder.names(in: oldRoot)

        #expect(throws: CocoaError.self) {
            try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)
        }
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == before)
        #expect(LibraryMoveTestFolder.names(in: newRoot) == before)
        Self.expectCompleteLibrary(at: oldRoot)
    }

    @Test func refusesAFile() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        let newRoot = try folder.write("New")
        let before = LibraryMoveTestFolder.names(in: oldRoot)

        #expect(throws: CocoaError.self) {
            try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)
        }
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == before)
    }

    @Test func refusesAFolderInsideTheItemsToMove() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        let before = LibraryMoveTestFolder.names(in: oldRoot)
        let insideDay = oldRoot.appending(path: "2026-10-06/New", directoryHint: .isDirectory)
        let insideMetadata = oldRoot.appending(path: ".ithil/New", directoryHint: .isDirectory)
        let dayItself = oldRoot.appending(component: "2026-10-14", directoryHint: .isDirectory)

        for newRoot in [insideDay, insideMetadata, dayItself] {
            #expect(throws: CocoaError.self) {
                try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)
            }
        }
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == before)
        #expect(!FileManager.default.fileExists(atPath: insideDay.path))
        #expect(!FileManager.default.fileExists(atPath: insideMetadata.path))
        Self.expectCompleteLibrary(at: oldRoot)
    }

    @Test func refusesAMissingLibraryFolder() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = folder.url.appending(component: "Missing", directoryHint: .isDirectory)
        let newRoot = folder.url.appending(component: "New", directoryHint: .isDirectory)

        #expect(throws: CocoaError.self) {
            try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: fileSystem)
        }
        #expect(!FileManager.default.fileExists(atPath: newRoot.path))
    }

    @Test func aFailedMoveMovesEverythingBack() throws {
        let folder = try LibraryMoveTestFolder()
        defer { folder.remove() }
        let oldRoot = try folder.makeLibrary("Old")
        try folder.write("Old/My notes.txt")
        let newRoot = folder.url.appending(component: "New", directoryHint: .isDirectory)
        let before = LibraryMoveTestFolder.names(in: oldRoot)
        // `.ithil` moves last, after both day folders have moved.
        let failing = LibraryMoveFailingFileSystem(failingName: ".ithil")

        #expect(throws: CocoaError.self) {
            try LibraryMove.move(from: oldRoot, to: newRoot, fileSystem: failing)
        }
        #expect(LibraryMoveTestFolder.names(in: oldRoot) == before)
        #expect(LibraryMoveTestFolder.names(in: newRoot).isEmpty)
        Self.expectCompleteLibrary(at: oldRoot)
    }
}

/// A unique temporary folder for the LibraryMove tests.
private struct LibraryMoveTestFolder {
    /// The files `makeLibrary(_:)` writes, by path inside the library folder.
    static let libraryFiles = [
        ".ithil/events.json",
        ".ithil/backups/events-20261006-120000.json",
        "2026-10-06/14.00 Physics Lecture/notes.md",
        "2026-10-06/14.00 Physics Lecture/.ithil-event",
        "2026-10-14/Mara's birthday/card.pdf",
    ]

    let url: URL

    init() throws {
        let name = "IthilLibraryMoveTests-\(UUID().uuidString)"
        url = FileManager.default.temporaryDirectory.appending(component: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `contents(of:)` to a file at `path` (relative, may contain slashes), creating its folders.
    @discardableResult
    func write(_ path: String) throws -> URL {
        let file = url.appending(path: path, directoryHint: .notDirectory)
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data(Self.contents(of: file).utf8).write(to: file)
        return file
    }

    /// A library folder named `name` with every file in `libraryFiles`: events.json and a backup, and
    /// two day folders with an event folder each (one with a marker).
    func makeLibrary(_ name: String) throws -> URL {
        for path in Self.libraryFiles {
            try write("\(name)/\(path)")
        }
        return url.appending(component: name, directoryHint: .isDirectory)
    }

    /// What `write(_:)` puts in a file: text naming it, so a mixed-up file doesn't compare equal.
    static func contents(of file: URL) -> String {
        "contents of \(file.lastPathComponent)"
    }

    /// The names of the items directly in `folder`, hidden ones included; empty if it doesn't exist.
    static func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }
}

/// A real file system that can't move one item (by name), like a folder locked by another app.
private struct LibraryMoveFailingFileSystem: FileSystem {
    var failingName: String
    let base = LocalFileSystem()

    func moveItem(at source: URL, to destination: URL) throws {
        if source.lastPathComponent == failingName {
            throw CocoaError(.fileWriteNoPermission)
        }
        try base.moveItem(at: source, to: destination)
    }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws { try base.writeAtomically(data, to: url) }
    func copyItem(at source: URL, to destination: URL) throws { try base.copyItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func trashItem(at url: URL) throws { try base.trashItem(at: url) }
    func modificationDate(at url: URL) -> Date? { base.modificationDate(at: url) }
}
