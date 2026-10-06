import Foundation
import IthilCore
import Testing

struct FileImportTests {
    private let fileSystem = LocalFileSystem()

    private func availableName(_ name: String, in folder: URL) -> String {
        FileImport.availableName(for: name, in: folder, fileSystem: fileSystem)
    }

    /// `FileImport.copy`, collecting its progress reports in `recorder`.
    private static func copy(
        _ sources: [URL],
        into folder: URL,
        root: URL,
        fileSystem: any FileSystem = LocalFileSystem(),
        recorder: FileImportProgressRecorder = FileImportProgressRecorder()
    ) async throws -> [URL] {
        try await FileImport.copy(sources, into: folder, root: root, fileSystem: fileSystem) { recorder.record($0) }
    }

    private static func isOutsideRoot(_ error: EventFoldersError?) -> Bool {
        guard case .outsideRoot = error else { return false }
        return true
    }

    private static func isNotADirectory(_ error: EventFoldersError?) -> Bool {
        guard case .notADirectory = error else { return false }
        return true
    }

    // MARK: - Progress

    @Test func fractionCompletedFollowsBytesThenItems() {
        let halfway = FileCopyProgress(completedBytes: 50, totalBytes: 200, completedFiles: 0, totalFiles: 2)
        let emptyFiles = FileCopyProgress(completedBytes: 0, totalBytes: 0, completedFiles: 1, totalFiles: 4)
        let overshoot = FileCopyProgress(completedBytes: 300, totalBytes: 200, completedFiles: 2, totalFiles: 2)
        #expect(halfway.fractionCompleted == 0.25)
        #expect(emptyFiles.fractionCompleted == 0.25)
        #expect(overshoot.fractionCompleted == 1)
        #expect(FileCopyProgress().fractionCompleted == 0)
    }

    // MARK: - Available names

    @Test func availableNameKeepsAFreeName() throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        #expect(availableName("notes.md", in: fixture.event) == "notes.md")
        #expect(availableName("Photos", in: fixture.event) == "Photos")
    }

    @Test func availableNameCountsUpLikeFinder() throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let folder = fixture.event
        try fixture.makeFile("notes.md", in: folder, count: 1)
        #expect(availableName("notes.md", in: folder) == "notes 2.md")
        try fixture.makeFile("notes 2.md", in: folder, count: 1)
        #expect(availableName("notes.md", in: folder) == "notes 3.md")
        try fixture.makeFile("notes 3.md", in: folder, count: 1)
        #expect(availableName("notes.md", in: folder) == "notes 4.md")
    }

    @Test func availableNameWithoutAnExtension() throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let folder = fixture.event
        try fixture.makeDirectory("Photos", in: folder)
        #expect(availableName("Photos", in: folder) == "Photos 2")
        try fixture.makeDirectory("Photos 2", in: folder)
        #expect(availableName("Photos", in: folder) == "Photos 3")
        #expect(availableName("Photos 2", in: folder) == "Photos 3")
        // A last part without letters, or with spaces, isn't an extension.
        try fixture.makeDirectory("Chapter 1.2", in: folder)
        #expect(availableName("Chapter 1.2", in: folder) == "Chapter 1.2 2")
        try fixture.makeFile("Notes from Dr. Smith", in: folder, count: 1)
        #expect(availableName("Notes from Dr. Smith", in: folder) == "Notes from Dr. Smith 2")
    }

    @Test func availableNameContinuesAnExistingNumber() throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let folder = fixture.event
        try fixture.makeFile("Report 2.pdf", in: folder, count: 1)
        #expect(availableName("Report 2.pdf", in: folder) == "Report 3.pdf")
        try fixture.makeFile("Report 3.pdf", in: folder, count: 1)
        #expect(availableName("Report 2.pdf", in: folder) == "Report 4.pdf")
        // Only a number like the ones Finder adds is continued: not a year, not one with a leading zero.
        try fixture.makeFile("Report 2026.pdf", in: folder, count: 1)
        #expect(availableName("Report 2026.pdf", in: folder) == "Report 2026 2.pdf")
        try fixture.makeFile("Track 01.mp3", in: folder, count: 1)
        #expect(availableName("Track 01.mp3", in: folder) == "Track 01 2.mp3")
        // Only the last extension is kept apart.
        try fixture.makeFile("archive.tar.gz", in: folder, count: 1)
        #expect(availableName("archive.tar.gz", in: folder) == "archive.tar 2.gz")
    }

    @Test func availableNameForNamesStartingWithADot() throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let folder = fixture.event
        try fixture.makeFile(".hidden", in: folder, count: 1)
        #expect(availableName(".hidden", in: folder) == ".hidden 2")
        try fixture.makeFile(".env.local", in: folder, count: 1)
        #expect(availableName(".env.local", in: folder) == ".env 2.local")
    }

    @Test func availableNameNeverUsesIthilsOwnNames() throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let folder = fixture.event
        #expect(availableName(".ithil-event", in: folder) == ".ithil-event 2")
        #expect(availableName(".Ithil-Event", in: folder) == ".Ithil-Event 2")
        #expect(availableName(".ithil-copying-1234", in: folder) == "ithil-copying-1234")
    }

    // MARK: - Copying

    @Test func copyKeepsTheOriginalsAndCopiesEveryByte() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let slides = try fixture.makeFile("Slides.pdf", count: 300_000, seed: 3)
        let notes = try fixture.makeFile("notes.md", count: 1_234, seed: 9)
        let event = fixture.event
        let root = fixture.root

        let copied = try await Self.copy([slides, notes], into: event, root: root)

        #expect(copied.map(\.lastPathComponent) == ["Slides.pdf", "notes.md"])
        for (original, copiedFile) in zip([slides, notes], copied) {
            #expect(try Data(contentsOf: copiedFile) == Data(contentsOf: original))
            #expect(copiedFile.deletingLastPathComponent().lastPathComponent == event.lastPathComponent)
        }
        #expect(try Data(contentsOf: slides) == FileImportTestFixture.pattern(count: 300_000, seed: 3))
        #expect(FileImportTestFixture.names(in: fixture.sources) == ["Slides.pdf", "notes.md"])
        #expect(FileImportTestFixture.names(in: event) == ["Slides.pdf", "notes.md"])
    }

    @Test func copyResolvesNameClashesLikeFinder() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let existing = try fixture.makeFile("notes.md", in: fixture.event, count: 10, seed: 1)
        let first = try fixture.makeFile("Week 1/notes.md", count: 20, seed: 2)
        let second = try fixture.makeFile("Week 2/notes.md", count: 30, seed: 3)
        let event = fixture.event
        let root = fixture.root

        let copied = try await Self.copy([first, second], into: event, root: root)

        try #require(copied.count == 2)
        #expect(copied.map(\.lastPathComponent) == ["notes 2.md", "notes 3.md"])
        #expect(try Data(contentsOf: copied[0]) == Data(contentsOf: first))
        #expect(try Data(contentsOf: copied[1]) == Data(contentsOf: second))
        #expect(try Data(contentsOf: existing) == FileImportTestFixture.pattern(count: 10, seed: 1))
        #expect(FileImportTestFixture.names(in: event) == ["notes.md", "notes 2.md", "notes 3.md"])
    }

    @Test func progressNeverGoesBackAndEndsAtTheTotal() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let sizes = [200_000, 0, 54_321]
        var sources: [URL] = []
        for (index, size) in sizes.enumerated() {
            let source = try fixture.makeFile("file \(index).bin", count: size, seed: UInt8(index))
            sources.append(source)
        }
        let recorder = FileImportProgressRecorder()

        _ = try await Self.copy(sources, into: fixture.event, root: fixture.root, recorder: recorder)

        let reports = recorder.reports
        let total = Int64(sizes.reduce(0, +))
        let first = try #require(reports.first)
        let last = try #require(reports.last)
        FileImportProgressRecorder.expectSteadyProgress(reports, totalBytes: total, totalFiles: 3)
        #expect(first.completedBytes == 0)
        #expect(first.currentName == "file 0.bin")
        #expect(last.completedBytes == total)
        #expect(last.completedFiles == 3)
        #expect(last.currentName == nil)
        #expect(last.fractionCompleted == 1)
    }

    @Test func progressIsReportedWhileAnItemIsStillCopying() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let intro = try fixture.makeFile("intro.txt", count: 1_000)
        let lecture = try fixture.makeFile("lecture.mov", count: 250_000, seed: 5)
        let gated = FileImportGatedFileSystem(gatedName: "lecture.mov")
        defer { gated.letCopyReturn() }
        let recorder = FileImportProgressRecorder()
        let event = fixture.event
        let root = fixture.root

        let copying = Task {
            try await Self.copy([intro, lecture], into: event, root: root, fileSystem: gated, recorder: recorder)
        }
        try await gated.waitUntilHoldingCopy()
        // The lecture is on disk under its temporary name, but its copy hasn't returned yet.
        try await recorder.waitForReport { $0.completedFiles == 1 && $0.completedBytes == 251_000 }
        #expect(FileImportTestFixture.names(in: event).contains("intro.txt"))
        #expect(!FileImportTestFixture.names(in: event).contains("lecture.mov"))
        gated.letCopyReturn()
        let copied = try await copying.value

        #expect(copied.map(\.lastPathComponent) == ["intro.txt", "lecture.mov"])
        FileImportProgressRecorder.expectSteadyProgress(recorder.reports, totalBytes: 251_000, totalFiles: 2)
        #expect(recorder.reports.last?.completedBytes == 251_000)
        #expect(FileImportTestFixture.names(in: event) == ["intro.txt", "lecture.mov"])
    }

    @Test func copiesAFolderWithEverythingInIt() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let photos = try fixture.makeDirectory("Lab Photos", in: fixture.sources)
        try fixture.makeFile("a.jpg", in: photos, count: 1_000, seed: 1)
        try fixture.makeFile("Day 2/b.jpg", in: photos, count: 2_000, seed: 2)
        try fixture.makeFile(".hidden", in: photos, count: 10, seed: 3)
        // A file already has the folder's name.
        try fixture.makeFile("Lab Photos", in: fixture.event, count: 5)
        let recorder = FileImportProgressRecorder()
        let event = fixture.event

        let copied = try await Self.copy([photos], into: event, root: fixture.root, recorder: recorder)

        let folder = try #require(copied.first)
        #expect(folder.lastPathComponent == "Lab Photos 2")
        for path in ["a.jpg", "Day 2/b.jpg", ".hidden"] {
            let copiedFile = folder.appending(path: path, directoryHint: .notDirectory)
            let original = photos.appending(path: path, directoryHint: .notDirectory)
            #expect(try Data(contentsOf: copiedFile) == Data(contentsOf: original))
        }
        #expect(FileImportTestFixture.names(in: photos) == ["a.jpg", "Day 2", ".hidden"])
        FileImportProgressRecorder.expectSteadyProgress(recorder.reports, totalBytes: 3_010, totalFiles: 1)
        #expect(recorder.reports.last?.completedBytes == 3_010)
        #expect(FileImportTestFixture.names(in: event) == ["Lab Photos", "Lab Photos 2"])
    }

    @Test func copyingAFolderIntoItselfIsRefused() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let root = fixture.root
        let event = fixture.event

        await #expect(throws: (any Error).self) {
            try await Self.copy([root], into: event, root: root)
        }
        #expect(FileImportTestFixture.names(in: event).isEmpty)
    }

    // MARK: - Failures and cancellation

    @Test func aMissingSourceStopsTheCopyButKeepsEarlierFiles() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let first = try fixture.makeFile("first.txt", count: 100)
        let missing = fixture.sources.appending(component: "missing.txt", directoryHint: .notDirectory)
        let last = try fixture.makeFile("last.txt", count: 100)
        let event = fixture.event
        let root = fixture.root

        await #expect(throws: (any Error).self) {
            try await Self.copy([first, missing, last], into: event, root: root)
        }
        #expect(FileImportTestFixture.names(in: event) == ["first.txt"])
        #expect(try Data(contentsOf: event.appending(component: "first.txt")) == Data(contentsOf: first))
    }

    @Test func aCopyThatFailsPartWayLeavesNoHalfFinishedItem() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let first = try fixture.makeFile("first.txt", count: 100)
        let big = try fixture.makeFile("big.mov", count: 5_000)
        let failing = FileImportFailingFileSystem(failingName: "big.mov")
        let event = fixture.event
        let root = fixture.root

        await #expect(throws: CocoaError.self) {
            try await Self.copy([first, big], into: event, root: root, fileSystem: failing)
        }
        #expect(FileImportTestFixture.names(in: event) == ["first.txt"])
        #expect(try Data(contentsOf: big) == FileImportTestFixture.pattern(count: 5_000, seed: 1))
    }

    @Test func cancellingDuringALargeCopyRemovesTheUnfinishedItem() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let intro = try fixture.makeFile("intro.txt", count: 1_000)
        let lecture = fixture.sources.appending(component: "lecture.mov", directoryHint: .notDirectory)
        try Data(count: 5_000_000).write(to: lecture)
        let outro = try fixture.makeFile("outro.txt", count: 1_000)
        let gated = FileImportGatedFileSystem(gatedName: "lecture.mov")
        defer { gated.letCopyReturn() }
        let event = fixture.event
        let root = fixture.root

        let copying = Task {
            try await Self.copy([intro, lecture, outro], into: event, root: root, fileSystem: gated)
        }
        try await gated.waitUntilHoldingCopy()
        copying.cancel()
        gated.letCopyReturn()

        await #expect(throws: CancellationError.self) {
            try await copying.value
        }
        #expect(FileImportTestFixture.names(in: event) == ["intro.txt"])
        #expect(FileImportTestFixture.names(in: fixture.sources) == ["intro.txt", "lecture.mov", "outro.txt"])
    }

    @Test func aCancelledTaskCopiesNothing() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let notes = try fixture.makeFile("notes.md", count: 100)
        let event = fixture.event
        let root = fixture.root

        let copying = Task {
            // Ends as soon as the task is cancelled, so the copy below always starts cancelled.
            try? await Task.sleep(for: .seconds(30))
            return try await Self.copy([notes], into: event, root: root)
        }
        copying.cancel()

        await #expect(throws: CancellationError.self) {
            try await copying.value
        }
        #expect(FileImportTestFixture.names(in: event).isEmpty)
    }

    // MARK: - Staying inside the library

    @Test func refusesFoldersOutsideTheLibrary() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let notes = try fixture.makeFile("notes.md", count: 100)
        let root = fixture.root
        let elsewhere = try fixture.makeDirectory("Elsewhere", in: fixture.base)
        let linked = root.appending(component: "Linked", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: elsewhere)
        let destinations = [
            elsewhere,
            fixture.event.appending(path: "../../../Elsewhere", directoryHint: .isDirectory),
            linked,
            linked.appending(component: "Sub", directoryHint: .isDirectory),
            root,
        ]

        for destination in destinations {
            let error = await #expect(throws: EventFoldersError.self) {
                try await Self.copy([notes], into: destination, root: root)
            }
            #expect(Self.isOutsideRoot(error))
        }
        #expect(FileImportTestFixture.names(in: elsewhere).isEmpty)
        #expect(FileImportTestFixture.names(in: root) == ["2026-10-06", "Linked"])
    }

    @Test func refusesAMissingFolder() async throws {
        let fixture = try FileImportTestFixture()
        defer { fixture.remove() }
        let notes = try fixture.makeFile("notes.md", count: 100)
        let root = fixture.root
        let missing = root.appending(path: "2026-10-07/09.00 Lab", directoryHint: .isDirectory)

        let error = await #expect(throws: EventFoldersError.self) {
            try await Self.copy([notes], into: missing, root: root)
        }
        #expect(Self.isNotADirectory(error))
        #expect(FileImportTestFixture.names(in: root) == ["2026-10-06"])
    }
}

// MARK: - Test support

/// A temporary library for the FileImport tests, all under one unique temporary folder (`base`): `root`
/// is the library folder, `event` an event folder in it, `sources` a folder outside it to copy from.
struct FileImportTestFixture {
    let base: URL
    let root: URL
    let event: URL
    let sources: URL

    init() throws {
        let name = "IthilFileImportTests-\(UUID().uuidString)"
        let base = FileManager.default.temporaryDirectory.appending(component: name, directoryHint: .isDirectory)
        let root = base.appending(component: "Library", directoryHint: .isDirectory)
        let event = root.appending(path: "2026-10-06/14.00 Physics Lecture", directoryHint: .isDirectory)
        let sources = base.appending(component: "Sources", directoryHint: .isDirectory)
        for folder in [event, sources] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.base = base
        self.root = root
        self.event = event
        self.sources = sources
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    /// Writes `count` bytes of `pattern(count:seed:)` to `path` (which may contain slashes) in `folder`
    /// (default: `sources`), creating the folders on the way.
    @discardableResult
    func makeFile(_ path: String, in folder: URL? = nil, count: Int, seed: UInt8 = 1) throws -> URL {
        let file = (folder ?? sources).appending(path: path, directoryHint: .notDirectory)
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Self.pattern(count: count, seed: seed).write(to: file)
        return file
    }

    @discardableResult
    func makeDirectory(_ name: String, in folder: URL) throws -> URL {
        let directory = folder.appending(component: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Bytes that differ from one position and seed to the next, so a copy that drops or shifts any
    /// byte doesn't compare equal.
    static func pattern(count: Int, seed: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            let value: Int = index &* 7 &+ Int(seed)
            bytes[index] = UInt8(truncatingIfNeeded: value)
        }
        return Data(bytes)
    }

    /// The names of the items directly in `folder`, hidden ones included; empty if it doesn't exist.
    static func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }
}

/// Collects progress reports from any thread.
final class FileImportProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [FileCopyProgress] = []

    var reports: [FileCopyProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ progress: FileCopyProgress) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(progress)
    }

    /// Returns once a report matching `condition` has arrived; fails after 10 seconds.
    func waitForReport(where condition: (FileCopyProgress) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !reports.contains(where: condition) {
            try #require(Date() < deadline, "No matching progress report arrived")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Checks that no count ever goes back and that the totals never change.
    static func expectSteadyProgress(_ reports: [FileCopyProgress], totalBytes: Int64, totalFiles: Int) {
        for (earlier, later) in zip(reports, reports.dropFirst()) {
            #expect(later.completedBytes >= earlier.completedBytes)
            #expect(later.completedFiles >= earlier.completedFiles)
        }
        for report in reports {
            #expect(report.totalBytes == totalBytes)
            #expect(report.totalFiles == totalFiles)
            #expect(report.completedBytes <= totalBytes)
        }
    }
}

/// A real file system whose copy of one item (by name) finishes on disk and then waits, without
/// returning, until `letCopyReturn()`: a copy caught in flight, for the cancellation and progress tests.
final class FileImportGatedFileSystem: FileSystem, @unchecked Sendable {
    private let gatedName: String
    private let base = LocalFileSystem()
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var isHolding = false

    init(gatedName: String) {
        self.gatedName = gatedName
    }

    var isHoldingCopy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHolding
    }

    /// Lets the held copy return (or the next one not wait at all).
    func letCopyReturn() {
        gate.signal()
    }

    /// Returns once the gated copy is being held; fails after 10 seconds.
    func waitUntilHoldingCopy() async throws {
        let deadline = Date().addingTimeInterval(10)
        while !isHoldingCopy {
            try #require(Date() < deadline, "The gated copy never started")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try base.copyItem(at: source, to: destination)
        guard source.lastPathComponent == gatedName else { return }
        setHolding()
        _ = gate.wait(timeout: .now() + 10)
    }

    private func setHolding() {
        lock.lock()
        defer { lock.unlock() }
        isHolding = true
    }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws { try base.writeAtomically(data, to: url) }
    func moveItem(at source: URL, to destination: URL) throws { try base.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func trashItem(at url: URL) throws { try base.trashItem(at: url) }
    func modificationDate(at url: URL) -> Date? { base.modificationDate(at: url) }
}

/// A real file system whose copy of one item (by name) fails part-way, like a disk filling up: half a
/// file is left at the destination and the copy throws.
struct FileImportFailingFileSystem: FileSystem {
    var failingName: String
    let base = LocalFileSystem()

    func copyItem(at source: URL, to destination: URL) throws {
        guard source.lastPathComponent != failingName else {
            try Data("half a file".utf8).write(to: destination)
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try base.copyItem(at: source, to: destination)
    }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws { try base.writeAtomically(data, to: url) }
    func moveItem(at source: URL, to destination: URL) throws { try base.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func trashItem(at url: URL) throws { try base.trashItem(at: url) }
    func modificationDate(at url: URL) -> Date? { base.modificationDate(at: url) }
}
