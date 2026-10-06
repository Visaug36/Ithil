import Foundation
import os

/// Why a library couldn't be loaded or saved.
public enum LibraryStoreError: Error, Equatable, Sendable {
    /// Nothing to load and nothing to recover from (or the library folder itself is missing).
    case noLibrary
    /// events.json was written by a newer Ithil. The folder is opened read-only and never overwritten.
    case newerSchema(found: Int, supported: Int)
    /// events.json is damaged and no backup or safety copy could be loaded. The text is a technical
    /// detail for logs, not for display.
    case unreadable(String)
    /// `save(_:)` after loading a file from a newer Ithil.
    case readOnly
}

/// How a damaged or missing events.json was recovered, so the app can tell the user.
public struct RecoveryReport: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// A file in `.ithil/backups/`.
        case backup(URL)
        /// The safety copy in Application Support.
        case safetyCopy(URL)

        public var url: URL {
            switch self {
            case .backup(let url), .safetyCopy(let url): return url
            }
        }
    }

    public var source: Source
    /// When the recovered copy was saved, if it says.
    public var recoveredSavedAt: Date?
    /// Where the damaged events.json was set aside; nil when it was missing.
    public var damagedFileMovedTo: URL?

    public init(source: Source, recoveredSavedAt: Date?, damagedFileMovedTo: URL?) {
        self.source = source
        self.recoveredSavedAt = recoveredSavedAt
        self.damagedFileMovedTo = damagedFileMovedTo
    }
}

/// The result of `LibraryStore.load()`.
public struct LibraryLoad: Hashable, Sendable {
    public var library: Library
    /// Set when events.json was missing or damaged and the library came from a backup or safety copy.
    public var recovery: RecoveryReport?

    public init(library: Library, recovery: RecoveryReport?) {
        self.library = library
        self.recovery = recovery
    }
}

/// Loads and saves one Ithil folder's events.json, with rolling backups, a safety copy outside the
/// folder and recovery from either.
///
/// ```
/// <root>/.ithil/events.json
/// <root>/.ithil/backups/events-yyyyMMdd-HHmmss.json        (UTC; "-2", "-3"… within one second)
/// <root>/.ithil/events.corrupt-yyyyMMdd-HHmmss.json        (a damaged file, set aside, never deleted)
/// <safetyDirectory>/<library id>.json
/// ```
///
/// All disk work happens on the actor, never on the caller's thread. Call `load()` or `create(_:)`
/// before `save(_:)`; a save without one first checks the events.json it would replace, so it can
/// never overwrite a file from a newer Ithil or destroy a damaged one. Nothing is written outside
/// `root` except the safety copy, and nothing is written at all if `root` is missing (a moved folder
/// or an unplugged drive).
public actor LibraryStore {
    /// The library folder chosen by the user.
    public nonisolated let root: URL

    private let safetyDirectory: URL
    private var knownLibraryID: UUID?
    private let fileSystem: any FileSystem
    private let timeSource: any TimeSource
    private let backupInterval: TimeInterval
    private let maxBackups: Int

    private let metadataFolder: URL
    private let eventsFile: URL
    private let backupsFolder: URL
    private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "LibraryStore")

    /// Set when events.json was written by a newer Ithil.
    private var isReadOnly = false
    /// Set once events.json has been loaded, created or checked, so `save(_:)` knows what it replaces.
    private var hasCheckedEventsFile = false
    /// The schema of the file last loaded; an older one forces a backup before the first save rewrites it.
    private var loadedSchemaVersion = LibraryCodec.currentSchemaVersion

    /// - Parameters:
    ///   - root: The library folder (the one containing `.ithil`).
    ///   - safetyDirectory: Where safety copies live, e.g. Application Support/Ithil/SafetyCopies.
    ///   - knownLibraryID: The ID of the library last opened from this folder, used to find its safety
    ///     copy when events.json is damaged. nil uses the ID found in the newest backup.
    ///   - backupInterval: The minimum time between backups.
    ///   - maxBackups: How many backups to keep; 0 turns backups off.
    public init(
        root: URL,
        safetyDirectory: URL,
        knownLibraryID: UUID?,
        fileSystem: any FileSystem,
        timeSource: any TimeSource,
        backupInterval: TimeInterval,
        maxBackups: Int
    ) {
        self.root = root
        self.safetyDirectory = safetyDirectory
        self.knownLibraryID = knownLibraryID
        self.fileSystem = fileSystem
        self.timeSource = timeSource
        self.backupInterval = backupInterval
        self.maxBackups = maxBackups
        let metadataFolder = root.appending(component: Self.metadataFolderName, directoryHint: .isDirectory)
        self.metadataFolder = metadataFolder
        self.eventsFile = metadataFolder.appending(component: Self.eventsFileName, directoryHint: .notDirectory)
        self.backupsFolder = metadataFolder.appending(component: Self.backupsFolderName, directoryHint: .isDirectory)
    }

    /// The hidden folder inside the root that holds events.json and its backups.
    static let metadataFolderName = ".ithil"
    static let eventsFileName = "events.json"
    static let backupsFolderName = "backups"

    // MARK: - Loading

    /// Reads events.json, migrating an older schema in memory.
    ///
    /// If it is missing or damaged, the newest backup or safety copy that decodes (by `savedAt`) is
    /// used: the damaged file is moved to `.ithil/events.corrupt-….json`, the recovered library is
    /// written back as events.json, and the result carries a `RecoveryReport`.
    ///
    /// Throws `noLibrary` when there's nothing to load (or `root` is missing), `unreadable` when
    /// events.json is damaged and nothing could be recovered (it is then left untouched), and
    /// `newerSchema` for a file from a newer Ithil, after which the store is read-only.
    public func load() throws -> LibraryLoad {
        isReadOnly = false
        hasCheckedEventsFile = false
        guard fileSystem.isDirectory(at: root) else {
            logger.error("The library folder is missing")
            throw LibraryStoreError.noLibrary
        }

        let eventsFileExists = fileSystem.fileExists(at: eventsFile)
        var damage: LibraryStoreError?
        if eventsFileExists {
            do {
                let data = try fileSystem.readData(at: eventsFile)
                let decoded = try LibraryCodec.decode(data)
                adopt(decoded)
                return LibraryLoad(library: decoded.library, recovery: nil)
            } catch let error as LibraryStoreError {
                if case .newerSchema = error {
                    isReadOnly = true
                    logger.notice("events.json is from a newer Ithil; opening read-only")
                    throw error
                }
                damage = error
            } catch {
                damage = .unreadable("events.json could not be read: \(error.localizedDescription)")
            }
            logger.error("events.json is damaged; looking for a backup")
        }

        guard let winner = recoveryCandidates().first else {
            logger.error("No backup or safety copy could be loaded")
            throw damage ?? LibraryStoreError.noLibrary
        }

        var damagedFileMovedTo: URL?
        if eventsFileExists {
            damagedFileMovedTo = try setDamagedEventsFileAside()
        }

        do {
            try fileSystem.createDirectory(at: metadataFolder)
            try fileSystem.writeAtomically(winner.data, to: eventsFile)
        } catch {
            // The library is still returned; the next save writes events.json again.
            let reason = String(describing: error)
            logger.error("Could not write the recovered events.json: \(reason, privacy: .private)")
        }

        adopt(winner.decoded)
        let kind = winner.isSafetyCopy ? "safety copy" : "backup"
        logger.notice("Recovered the library from a \(kind, privacy: .public)")
        let report = RecoveryReport(
            source: winner.source, recoveredSavedAt: winner.decoded.savedAt, damagedFileMovedTo: damagedFileMovedTo)
        return LibraryLoad(library: winner.decoded.library, recovery: report)
    }

    // MARK: - Writing

    /// Writes a brand-new library into the folder. Refuses (throws) if `root` is missing or already has
    /// an events.json, so an existing library is never replaced by an empty one.
    public func create(_ library: Library) throws {
        guard fileSystem.isDirectory(at: root) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: root])
        }
        guard !fileSystem.fileExists(at: eventsFile) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: eventsFile])
        }
        let data = try LibraryCodec.encode(library, savedAt: timeSource.now)
        try fileSystem.createDirectory(at: metadataFolder)
        try fileSystem.writeAtomically(data, to: eventsFile)
        isReadOnly = false
        hasCheckedEventsFile = true
        knownLibraryID = library.id
        loadedSchemaVersion = LibraryCodec.currentSchemaVersion
        writeSafetyCopy(data, libraryID: library.id)
    }

    /// Saves the library.
    ///
    /// If no backup was made within the last `backupInterval`, the current events.json is first copied
    /// into `backups/` and the oldest backups beyond `maxBackups` are removed. Then events.json is
    /// written atomically (a failure leaves the previous file intact and is thrown), and the same bytes
    /// go to the safety copy (a failure there is only logged).
    ///
    /// Throws `readOnly` without touching anything after loading a file from a newer Ithil. Without a
    /// successful `load()` or `create(_:)` first, the existing events.json is checked: one from a newer
    /// Ithil makes the store read-only, and a damaged one is set aside like in `load()`.
    public func save(_ library: Library) throws {
        guard !isReadOnly else { throw LibraryStoreError.readOnly }
        guard fileSystem.isDirectory(at: root) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: root])
        }
        if !hasCheckedEventsFile {
            try checkEventsFileBeforeFirstSave()
        }
        let now = timeSource.now
        let data = try LibraryCodec.encode(library, savedAt: now)
        try fileSystem.createDirectory(at: metadataFolder)
        backUpEventsFileIfDue(now: now)
        try fileSystem.writeAtomically(data, to: eventsFile)
        knownLibraryID = library.id
        loadedSchemaVersion = LibraryCodec.currentSchemaVersion
        writeSafetyCopy(data, libraryID: library.id)
    }

    // MARK: - Helpers

    private func adopt(_ decoded: DecodedLibrary) {
        knownLibraryID = decoded.library.id
        loadedSchemaVersion = decoded.schemaVersion
        isReadOnly = false
        hasCheckedEventsFile = true
    }

    /// Moves the damaged events.json to `.ithil/events.corrupt-yyyyMMdd-HHmmss.json` and returns where it
    /// went. Throws `unreadable` if it can't be moved, so it is never overwritten.
    private func setDamagedEventsFileAside() throws -> URL {
        let destination = uniqueTimestampedFile(in: metadataFolder, prefix: "events.corrupt-", date: timeSource.now)
        do {
            try fileSystem.moveItem(at: eventsFile, to: destination)
        } catch {
            let reason = String(describing: error)
            logger.error("Could not set the damaged events.json aside: \(reason, privacy: .private)")
            throw LibraryStoreError.unreadable("events.json is damaged and could not be set aside")
        }
        return destination
    }

    /// For a save that no successful `load()` or `create(_:)` preceded: refuses to replace a file from a
    /// newer Ithil (the store becomes read-only) and sets a damaged file aside instead of overwriting it.
    private func checkEventsFileBeforeFirstSave() throws {
        guard fileSystem.fileExists(at: eventsFile) else {
            hasCheckedEventsFile = true
            return
        }
        do {
            let decoded = try LibraryCodec.decode(fileSystem.readData(at: eventsFile))
            loadedSchemaVersion = decoded.schemaVersion
        } catch let error as LibraryStoreError {
            if case .newerSchema = error {
                isReadOnly = true
                logger.notice("events.json is from a newer Ithil; not saving over it")
                throw LibraryStoreError.readOnly
            }
            _ = try setDamagedEventsFileAside()
        } catch {
            _ = try setDamagedEventsFileAside()
        }
        hasCheckedEventsFile = true
    }

    private func safetyCopyFile(for libraryID: UUID) -> URL {
        safetyDirectory.appending(component: "\(libraryID.uuidString).json", directoryHint: .notDirectory)
    }

    private func writeSafetyCopy(_ data: Data, libraryID: UUID) {
        do {
            try fileSystem.createDirectory(at: safetyDirectory)
            try fileSystem.writeAtomically(data, to: safetyCopyFile(for: libraryID))
        } catch {
            let reason = String(describing: error)
            logger.error("Could not write the safety copy: \(reason, privacy: .private)")
        }
    }

    /// Copies events.json into `backups/` unless a backup was made within `backupInterval` of now
    /// (in either direction, so a clock set back doesn't stop backups), then prunes. Failures are
    /// logged: a missing backup must not stop the user's change from being saved.
    private func backUpEventsFileIfDue(now: Date) {
        guard maxBackups > 0, fileSystem.fileExists(at: eventsFile) else { return }
        let afterMigration = loadedSchemaVersion < LibraryCodec.currentSchemaVersion
        let existing = backupFiles()
        let hasRecentBackup = existing.contains { abs(now.timeIntervalSince($0.date)) < backupInterval }
        guard afterMigration || !hasRecentBackup else { return }
        // Within one second, number past every backup already there (even after older ones were pruned),
        // so the new backup always sorts newest and pruning never removes it.
        let stamp = LibraryStoreTimestamp.string(from: now)
        var highestCounter = 0
        for backup in existing where backup.stamp == stamp {
            highestCounter = max(highestCounter, backup.counter)
        }
        do {
            try fileSystem.createDirectory(at: backupsFolder)
            let destination = uniqueTimestampedFile(
                in: backupsFolder, prefix: "events-", date: now, firstCounter: highestCounter + 1)
            try fileSystem.copyItem(at: eventsFile, to: destination)
        } catch {
            let reason = String(describing: error)
            logger.error("Could not back up events.json: \(reason, privacy: .private)")
            return
        }
        pruneBackups()
    }

    /// Keeps the newest `maxBackups` backups, by the timestamp (and counter) in their names.
    private func pruneBackups() {
        let backups = backupFiles()
        guard backups.count > maxBackups else { return }
        for backup in backups.prefix(backups.count - maxBackups) {
            do {
                try fileSystem.removeItem(at: backup.url)
            } catch {
                let reason = String(describing: error)
                logger.error("Could not remove an old backup: \(reason, privacy: .private)")
            }
        }
    }

    /// Ithil's backups in `backups/`, oldest first. Other files there are ignored and never touched.
    private func backupFiles() -> [LibraryStoreBackupFile] {
        guard let contents = try? fileSystem.contentsOfDirectory(at: backupsFolder) else { return [] }
        var backups: [LibraryStoreBackupFile] = []
        for item in contents {
            if let backup = LibraryStoreBackupFile(name: item.lastPathComponent, in: backupsFolder) {
                backups.append(backup)
            }
        }
        return backups.sorted { ($0.stamp, $0.counter) < ($1.stamp, $1.counter) }
    }

    /// `<prefix>yyyyMMdd-HHmmss.json` for `date` (UTC), with "-2", "-3"… added if that name is taken.
    /// `firstCounter` skips numbers that must not be reused (1 is the plain name).
    private func uniqueTimestampedFile(in folder: URL, prefix: String, date: Date, firstCounter: Int = 1) -> URL {
        let stamp = LibraryStoreTimestamp.string(from: date)
        var counter = max(firstCounter, 1)
        var url = Self.timestampedFile(in: folder, prefix: prefix, stamp: stamp, counter: counter)
        while fileSystem.fileExists(at: url) {
            counter += 1
            url = Self.timestampedFile(in: folder, prefix: prefix, stamp: stamp, counter: counter)
        }
        return url
    }

    private static func timestampedFile(in folder: URL, prefix: String, stamp: String, counter: Int) -> URL {
        let name = counter == 1 ? "\(prefix)\(stamp).json" : "\(prefix)\(stamp)-\(counter).json"
        return folder.appending(component: name, directoryHint: .notDirectory)
    }

    /// Every backup and the safety copy that decodes, newest `savedAt` first. The safety copy is the one
    /// for `knownLibraryID`, or else for the library ID in the newest backup.
    private func recoveryCandidates() -> [LibraryStoreCandidate] {
        var backups: [LibraryStoreCandidate] = []
        for backup in backupFiles().reversed() {
            if let candidate = recoveryCandidate(at: backup.url, isSafetyCopy: false, order: backups.count) {
                backups.append(candidate)
            }
        }
        backups = LibraryStoreCandidate.newestFirst(backups)

        var candidates = backups
        if let libraryID = knownLibraryID ?? backups.first?.decoded.library.id {
            let safetyCopy = safetyCopyFile(for: libraryID)
            if let candidate = recoveryCandidate(at: safetyCopy, isSafetyCopy: true, order: candidates.count) {
                candidates.append(candidate)
            }
        }
        return LibraryStoreCandidate.newestFirst(candidates)
    }

    private func recoveryCandidate(at url: URL, isSafetyCopy: Bool, order: Int) -> LibraryStoreCandidate? {
        guard fileSystem.fileExists(at: url) else { return nil }
        do {
            let data = try fileSystem.readData(at: url)
            let decoded = try LibraryCodec.decode(data)
            return LibraryStoreCandidate(
                url: url, isSafetyCopy: isSafetyCopy, data: data, decoded: decoded, order: order)
        } catch {
            let name = url.lastPathComponent
            let reason = String(describing: error)
            logger.error("Skipping \(name, privacy: .private): \(reason, privacy: .private)")
            return nil
        }
    }
}

/// A backup or safety copy that decoded, with its bytes so it can be written back unchanged.
private struct LibraryStoreCandidate {
    var url: URL
    var isSafetyCopy: Bool
    var data: Data
    var decoded: DecodedLibrary
    /// Tie-breaker for equal `savedAt`: lower wins (newer backups come first, the safety copy last).
    var order: Int

    var source: RecoveryReport.Source {
        isSafetyCopy ? .safetyCopy(url) : .backup(url)
    }

    static func newestFirst(_ candidates: [LibraryStoreCandidate]) -> [LibraryStoreCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsSavedAt = lhs.decoded.savedAt ?? .distantPast
            let rhsSavedAt = rhs.decoded.savedAt ?? .distantPast
            if lhsSavedAt != rhsSavedAt { return lhsSavedAt > rhsSavedAt }
            return lhs.order < rhs.order
        }
    }
}

/// A file in `backups/` named `events-yyyyMMdd-HHmmss.json` or `events-yyyyMMdd-HHmmss-N.json`.
private struct LibraryStoreBackupFile {
    var url: URL
    /// `yyyyMMdd-HHmmss`; fixed width, so it sorts chronologically as text.
    var stamp: String
    /// 1 for the plain name, N for a "-N" suffix.
    var counter: Int
    var date: Date

    init?(name: String, in folder: URL) {
        let prefix = "events-"
        let suffix = ".json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        guard name.count > prefix.count + suffix.count else { return nil }
        let core = name.dropFirst(prefix.count).dropLast(suffix.count)
        let pieces = core.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        let stamp = "\(pieces[0])-\(pieces[1])"
        guard let date = LibraryStoreTimestamp.date(from: stamp) else { return nil }
        var counter = 1
        if pieces.count == 3 {
            guard let number = Int(pieces[2]), number >= 2 else { return nil }
            counter = number
        }
        self.url = folder.appending(component: name, directoryHint: .notDirectory)
        self.stamp = stamp
        self.counter = counter
        self.date = date
    }
}

/// `yyyyMMdd-HHmmss` timestamps in UTC, built from calendar components (no DateFormatter, so the
/// user's locale and calendar can't change them).
private enum LibraryStoreTimestamp {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func string(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return "\(day)-\(time)"
    }

    /// Parses `yyyyMMdd-HHmmss`; nil for anything else, including impossible dates.
    static func date(from text: String) -> Date? {
        let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces[0].count == 8, pieces[1].count == 6 else { return nil }
        guard let day = Int(pieces[0]), let time = Int(pieces[1]) else { return nil }
        let parts = DateComponents(
            year: day / 10_000, month: day / 100 % 100, day: day % 100,
            hour: time / 10_000, minute: time / 100 % 100, second: time % 100)
        guard let date = calendar.date(from: parts), string(from: date) == text else { return nil }
        return date
    }
}
