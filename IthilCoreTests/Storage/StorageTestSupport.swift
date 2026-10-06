import Foundation
import IthilCore

/// A clock the storage tests move by hand.
final class StorageTestClock: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// A unique folder under the temporary directory. Call `remove()` when done (usually in a `defer`).
struct StorageTempFolder {
    let url: URL

    init() throws {
        let name = "IthilStorageTests-\(UUID().uuidString)"
        url = FileManager.default.temporaryDirectory.appending(component: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// A URL inside the folder; `path` may contain slashes. Nothing is created.
    func child(_ path: String) -> URL {
        url.appending(path: path, directoryHint: .isDirectory)
    }

    /// Creates a subfolder (and its parents; `name` may contain slashes) and returns it.
    func makeDirectory(_ name: String) throws -> URL {
        let directory = child(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }
}

/// A real file system whose atomic writes fail under one folder, like a full disk or a locked file.
struct StorageFaultyFileSystem: FileSystem {
    var failingWritesUnder: URL
    let base = LocalFileSystem()

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { base.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let folder = failingWritesUnder.path
        if url.path == folder || url.path.hasPrefix(folder + "/") {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try base.writeAtomically(data, to: url)
    }

    func copyItem(at source: URL, to destination: URL) throws { try base.copyItem(at: source, to: destination) }
    func moveItem(at source: URL, to destination: URL) throws { try base.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func trashItem(at url: URL) throws { try base.trashItem(at: url) }
    func modificationDate(at url: URL) -> Date? { base.modificationDate(at: url) }
}

/// Fixed dates, a sample library and file helpers for the storage tests.
enum StorageFixtures {
    /// Tuesday 2026-10-06 11:50:00 UTC (13:50 in Amsterdam), the design's mock "now".
    static let start = instant(year: 2026, month: 10, day: 6, hour: 11, minute: 50, zone: "UTC")

    static func timeZone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }

    /// A wall-clock time in an explicit time zone, on the Gregorian calendar.
    static func instant(year: Int, month: Int, day: Int, hour: Int, minute: Int, zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(zone)
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: parts)!
    }

    /// Two subjects (a palette and a custom color) and three events covering every stored field:
    /// a weekly timed lecture with exclusions, a multi-day all-day trip and a detached occurrence in
    /// another time zone. All timestamps are whole seconds.
    static func sampleLibrary() -> Library {
        let physics = Subject(name: "Physics", color: .palette(.clay), keywords: ["phys", "mechanics"])
        let personal = Subject(name: "Personal", color: SubjectColor(hexString: "#3366CC")!)
        let created = instant(year: 2026, month: 9, day: 1, hour: 8, minute: 0, zone: "UTC")
        let modified = instant(year: 2026, month: 9, day: 2, hour: 9, minute: 30, zone: "UTC")

        let lectureStart = instant(year: 2026, month: 10, day: 6, hour: 14, minute: 0, zone: "Europe/Amsterdam")
        let lectureEnd = instant(year: 2026, month: 10, day: 6, hour: 15, minute: 30, zone: "Europe/Amsterdam")
        let lastLecture = CalendarDate(year: 2026, month: 12, day: 18)
        let skipped: Set<CalendarDate> = [
            CalendarDate(year: 2026, month: 10, day: 20),
            CalendarDate(year: 2026, month: 11, day: 3),
        ]
        let lecture = Event(
            title: "Physics Lecture",
            timing: .timed(start: lectureStart, end: lectureEnd, timeZone: timeZone("Europe/Amsterdam")),
            subjectID: physics.id,
            location: "Room B/204",
            notes: "Slides: https://example.com/physics/week-6",
            alert: .tenMinutes,
            recurrence: RecurrenceRule(frequency: .weekly, until: lastLecture),
            excludedDates: skipped,
            createdAt: created,
            modifiedAt: modified)

        let tripStart = CalendarDate(year: 2026, month: 10, day: 9)
        let tripEnd = CalendarDate(year: 2026, month: 10, day: 11)
        let trip = Event(
            title: "Field Trip",
            timing: .allDay(start: tripStart, end: tripEnd),
            subjectID: personal.id,
            alert: .oneDay,
            createdAt: created)

        let movedStart = instant(year: 2026, month: 10, day: 21, hour: 9, minute: 0, zone: "Asia/Tokyo")
        let movedEnd = instant(year: 2026, month: 10, day: 21, hour: 10, minute: 30, zone: "Asia/Tokyo")
        let replaced = SeriesOccurrence(seriesID: lecture.id, date: CalendarDate(year: 2026, month: 10, day: 20))
        let moved = Event(
            title: "Physics Lecture",
            timing: .timed(start: movedStart, end: movedEnd, timeZone: timeZone("Asia/Tokyo")),
            subjectID: physics.id,
            detachedFrom: replaced,
            createdAt: created,
            modifiedAt: modified)

        return Library(subjects: [physics, personal], events: [lecture, trip, moved])
    }

    /// The names of the items in a folder, hidden ones included; empty if it doesn't exist.
    static func names(in folder: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return Set(contents.map(\.lastPathComponent))
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func metadataFolder(in root: URL) -> URL {
        root.appending(component: ".ithil", directoryHint: .isDirectory)
    }

    static func eventsFile(in root: URL) -> URL {
        metadataFolder(in: root).appending(component: "events.json", directoryHint: .notDirectory)
    }

    static func backupsFolder(in root: URL) -> URL {
        metadataFolder(in: root).appending(component: "backups", directoryHint: .isDirectory)
    }

    /// Backup file names, oldest first (plain lexicographic order is right for the cases tested).
    static func backupNames(in root: URL) -> [String] {
        names(in: backupsFolder(in: root)).sorted()
    }

    static func library(at url: URL) throws -> Library {
        try LibraryCodec.decode(Data(contentsOf: url)).library
    }

    static func makeStore(
        root: URL,
        safety: URL,
        knownLibraryID: UUID? = nil,
        clock: StorageTestClock,
        fileSystem: any FileSystem = LocalFileSystem(),
        backupInterval: TimeInterval = 60 * 60,
        maxBackups: Int = 10
    ) -> LibraryStore {
        LibraryStore(
            root: root, safetyDirectory: safety, knownLibraryID: knownLibraryID, fileSystem: fileSystem,
            timeSource: clock, backupInterval: backupInterval, maxBackups: maxBackups)
    }
}

/// Whether `error` is `LibraryStoreError.unreadable`, whatever its message.
func storageErrorIsUnreadable(_ error: (any Error)?) -> Bool {
    guard let storeError = error as? LibraryStoreError, case .unreadable = storeError else { return false }
    return true
}
