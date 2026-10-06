import Foundation
import IthilCore
import Testing

struct LibraryStoreTests {
    // MARK: - Create, save and load

    @Test func createThenLoadRoundTrips() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        let library = StorageFixtures.sampleLibrary()

        let store = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        #expect(store.root == root)
        try await store.create(library)

        let reopened = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        let load = try await reopened.load()
        #expect(load.library == library)
        #expect(load.recovery == nil)
    }

    @Test func savedFileIsPrettyJSONWithSchemaVersionOne() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(root: root, safety: folder.child("Safety"), clock: clock)
        try await store.create(StorageFixtures.sampleLibrary())

        let data = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        let object = try #require(parsed as? [String: Any])
        let version = object["schemaVersion"] as? Int
        let savedAt = object["savedAt"] as? String
        #expect(version == 1)
        #expect(savedAt == "2026-10-06T11:50:00Z")
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("{\n  \"events\""))
    }

    @Test func savesLeaveNoStrayFiles() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        var library = StorageFixtures.sampleLibrary()
        let store = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        try await store.create(library)
        for round in 1...5 {
            clock.advance(by: 10 * 60)
            library.events[0].title = "Physics Lecture \(round)"
            try await store.save(library)
        }

        #expect(StorageFixtures.names(in: root) == [".ithil"])
        #expect(StorageFixtures.names(in: StorageFixtures.metadataFolder(in: root)) == ["events.json", "backups"])
        #expect(StorageFixtures.names(in: safety) == ["\(library.id.uuidString).json"])
        let saved = try StorageFixtures.library(at: StorageFixtures.eventsFile(in: root))
        #expect(saved == library)
    }

    @Test func safetyCopyMatchesEventsJSONAfterEverySave() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        var library = StorageFixtures.sampleLibrary()
        let store = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        let safetyCopy = safety.appending(component: "\(library.id.uuidString).json", directoryHint: .notDirectory)

        let eventsFile = StorageFixtures.eventsFile(in: root)
        try await store.create(library)
        let createdCopy = try Data(contentsOf: safetyCopy)
        let createdFile = try Data(contentsOf: eventsFile)
        #expect(createdCopy == createdFile)

        clock.advance(by: 30)
        library.subjects.removeAll()
        try await store.save(library)
        let savedCopy = try Data(contentsOf: safetyCopy)
        let savedFile = try Data(contentsOf: eventsFile)
        #expect(savedCopy == savedFile)
        #expect(savedCopy != createdCopy)
    }

    @Test func createRefusesAFolderThatAlreadyHasALibrary() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let clock = StorageTestClock(StorageFixtures.start)
        let library = StorageFixtures.sampleLibrary()
        try await StorageFixtures.makeStore(root: root, safety: folder.child("Safety"), clock: clock).create(library)
        let before = try Data(contentsOf: StorageFixtures.eventsFile(in: root))

        let store = StorageFixtures.makeStore(root: root, safety: folder.child("Safety"), clock: clock)
        await #expect(throws: (any Error).self) {
            try await store.create(Library())
        }
        let after = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
        #expect(after == before)
    }

    @Test func createRefusesAMissingFolder() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let missing = folder.child("Missing")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(root: missing, safety: folder.child("Safety"), clock: clock)
        await #expect(throws: (any Error).self) {
            try await store.create(Library())
        }
        #expect(!StorageFixtures.exists(missing))
    }

    // MARK: - Backups

    @Test func backupsAreMadeAtMostOncePerIntervalAndPruned() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(
            root: root, safety: folder.child("Safety"), clock: clock, backupInterval: 60 * 60, maxBackups: 3)
        let eventsFile = StorageFixtures.eventsFile(in: root)
        var library = StorageFixtures.sampleLibrary()

        try await store.create(library)
        #expect(StorageFixtures.backupNames(in: root).isEmpty)

        // 11:50: there's no backup yet, so the created file is backed up first.
        let created = try Data(contentsOf: eventsFile)
        library.events[0].title = "Version 1"
        try await store.save(library)
        #expect(StorageFixtures.backupNames(in: root) == ["events-20261006-115000.json"])
        let firstBackup = StorageFixtures.backupsFolder(in: root).appending(component: "events-20261006-115000.json")
        let firstBackupData = try Data(contentsOf: firstBackup)
        #expect(firstBackupData == created)

        // 12:00: within the hour, no new backup.
        clock.advance(by: 10 * 60)
        library.events[0].title = "Version 2"
        try await store.save(library)
        #expect(StorageFixtures.backupNames(in: root) == ["events-20261006-115000.json"])

        // 12:50: an hour after the last backup, the current file (version 2) is backed up.
        clock.advance(by: 50 * 60)
        let version2 = try Data(contentsOf: eventsFile)
        library.events[0].title = "Version 3"
        try await store.save(library)
        #expect(StorageFixtures.backupNames(in: root) == ["events-20261006-115000.json", "events-20261006-125000.json"])
        let secondBackup = StorageFixtures.backupsFolder(in: root).appending(component: "events-20261006-125000.json")
        let secondBackupData = try Data(contentsOf: secondBackup)
        #expect(secondBackupData == version2)

        // Three more hours: only the newest three backups are kept.
        for hour in 1...3 {
            clock.advance(by: 60 * 60)
            library.events[0].title = "Version \(3 + hour)"
            try await store.save(library)
        }
        let expected = ["events-20261006-135000.json", "events-20261006-145000.json", "events-20261006-155000.json"]
        #expect(StorageFixtures.backupNames(in: root) == expected)
        let saved = try StorageFixtures.library(at: eventsFile)
        #expect(saved == library)
    }

    @Test func backupsInTheSameSecondGetANumberAndPruneByIt() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(
            root: root, safety: folder.child("Safety"), clock: clock, backupInterval: 0, maxBackups: 2)
        var library = StorageFixtures.sampleLibrary()
        try await store.create(library)

        var previous = Data()
        for round in 1...3 {
            previous = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
            library.events[0].title = "Round \(round)"
            try await store.save(library)
        }

        let names = StorageFixtures.backupNames(in: root)
        #expect(names == ["events-20261006-115000-2.json", "events-20261006-115000-3.json"])
        let newest = StorageFixtures.backupsFolder(in: root).appending(component: "events-20261006-115000-3.json")
        let newestData = try Data(contentsOf: newest)
        #expect(newestData == previous)

        // The plain name was pruned, but reusing it would make the newest backup sort oldest and be
        // pruned straight away: numbering carries on instead.
        previous = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
        library.events[0].title = "Round 4"
        try await store.save(library)
        let laterNames = StorageFixtures.backupNames(in: root)
        #expect(laterNames == ["events-20261006-115000-3.json", "events-20261006-115000-4.json"])
        let fourth = StorageFixtures.backupsFolder(in: root).appending(component: "events-20261006-115000-4.json")
        let fourthData = try Data(contentsOf: fourth)
        #expect(fourthData == previous)
    }

    @Test func otherFilesInTheBackupsFolderAreLeftAlone() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(
            root: root, safety: folder.child("Safety"), clock: clock, backupInterval: 0, maxBackups: 1)
        var library = StorageFixtures.sampleLibrary()
        try await store.create(library)
        let backups = StorageFixtures.backupsFolder(in: root)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true, attributes: nil)
        try Data("mine".utf8).write(to: backups.appending(component: "notes.txt"))

        for round in 1...3 {
            clock.advance(by: 1)
            library.events[0].title = "Round \(round)"
            try await store.save(library)
        }
        #expect(StorageFixtures.names(in: backups) == ["notes.txt", "events-20261006-115003.json"])
    }

    // MARK: - Recovery

    /// Three versions of a library with backups, an hour apart:
    /// - 11:50:00 create version 0
    /// - 11:51:00 save version 1 (backs up version 0 as events-20261006-115100.json)
    /// - 12:51:00 save version 2 (backs up version 1 as events-20261006-125100.json; safety copy = version 2)
    /// The clock is left at 12:52:00.
    private struct History {
        var root: URL
        var safety: URL
        var clock: StorageTestClock
        var versions: [Library]

        var eventsFile: URL { StorageFixtures.eventsFile(in: root) }
        var libraryID: UUID { versions[0].id }
    }

    private func makeHistory(in folder: StorageTempFolder) async throws -> History {
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        var library = StorageFixtures.sampleLibrary()
        var versions = [library]
        try await store.create(library)

        clock.advance(by: 60)
        library.events[0].title = "Physics Lecture (version 1)"
        versions.append(library)
        try await store.save(library)

        clock.advance(by: 60 * 60)
        library.events[0].title = "Physics Lecture (version 2)"
        versions.append(library)
        try await store.save(library)

        clock.advance(by: 60)
        return History(root: root, safety: safety, clock: clock, versions: versions)
    }

    private func backupName(_ source: RecoveryReport.Source) -> String? {
        guard case .backup(let url) = source else { return nil }
        return url.lastPathComponent
    }

    private func safetyCopyName(_ source: RecoveryReport.Source) -> String? {
        guard case .safetyCopy(let url) = source else { return nil }
        return url.lastPathComponent
    }

    @Test func corruptFileIsRecoveredFromTheNewestBackup() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        let garbage = Data("{\"schemaVersion\": 1, \"events\": [".utf8)
        try garbage.write(to: history.eventsFile)

        // A different safety folder, so only the backups can help.
        let store = StorageFixtures.makeStore(root: history.root, safety: folder.child("Other"), clock: history.clock)
        let load = try await store.load()

        #expect(load.library == history.versions[1])
        let report = try #require(load.recovery)
        #expect(backupName(report.source) == "events-20261006-125100.json")
        #expect(report.source.url.lastPathComponent == "events-20261006-125100.json")
        #expect(report.recoveredSavedAt == StorageFixtures.start.addingTimeInterval(60))

        let movedTo = try #require(report.damagedFileMovedTo)
        #expect(movedTo.lastPathComponent == "events.corrupt-20261006-125200.json")
        #expect(movedTo.deletingLastPathComponent().lastPathComponent == ".ithil")
        let movedData = try Data(contentsOf: movedTo)
        #expect(movedData == garbage)
        let restored = try StorageFixtures.library(at: history.eventsFile)
        #expect(restored == history.versions[1])

        // events.json is valid again: the next load needs no recovery.
        let reopened = StorageFixtures.makeStore(
            root: history.root, safety: folder.child("Other"), clock: history.clock)
        let again = try await reopened.load()
        #expect(again.library == history.versions[1])
        #expect(again.recovery == nil)

        // Damaged again in the same second: the second damaged file gets its own name.
        try garbage.write(to: history.eventsFile)
        let secondLoad = try await reopened.load()
        #expect(secondLoad.recovery?.damagedFileMovedTo?.lastPathComponent == "events.corrupt-20261006-125200-2.json")
        let metadataNames = StorageFixtures.names(in: StorageFixtures.metadataFolder(in: history.root))
        let expectedNames: Set<String> = [
            "events.json",
            "backups",
            "events.corrupt-20261006-125200.json",
            "events.corrupt-20261006-125200-2.json",
        ]
        #expect(metadataNames == expectedNames)
    }

    @Test func undecodableBackupsAreSkipped() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        try Data("garbage".utf8).write(to: history.eventsFile)
        let backups = StorageFixtures.backupsFolder(in: history.root)
        try Data().write(to: backups.appending(component: "events-20261006-125100.json"))

        let store = StorageFixtures.makeStore(root: history.root, safety: folder.child("Other"), clock: history.clock)
        let load = try await store.load()
        #expect(load.library == history.versions[0])
        let report = try #require(load.recovery)
        #expect(backupName(report.source) == "events-20261006-115100.json")
    }

    @Test func safetyCopyNewerThanEveryBackupWins() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        try Data("garbage".utf8).write(to: history.eventsFile)

        let store = StorageFixtures.makeStore(
            root: history.root, safety: history.safety, knownLibraryID: history.libraryID, clock: history.clock)
        let load = try await store.load()
        #expect(load.library == history.versions[2])
        let report = try #require(load.recovery)
        #expect(safetyCopyName(report.source) == "\(history.libraryID.uuidString).json")
        #expect(report.recoveredSavedAt == StorageFixtures.start.addingTimeInterval(61 * 60))
        #expect(report.damagedFileMovedTo != nil)
        let restored = try StorageFixtures.library(at: history.eventsFile)
        #expect(restored == history.versions[2])
    }

    @Test func safetyCopyIsFoundThroughTheBackupsWhenTheIDIsUnknown() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        try Data("garbage".utf8).write(to: history.eventsFile)

        let store = StorageFixtures.makeStore(root: history.root, safety: history.safety, clock: history.clock)
        let load = try await store.load()
        #expect(load.library == history.versions[2])
        let report = try #require(load.recovery)
        #expect(safetyCopyName(report.source) == "\(history.libraryID.uuidString).json")
    }

    @Test func missingLibraryIsRecoveredFromTheSafetyCopy() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        try FileManager.default.removeItem(at: StorageFixtures.metadataFolder(in: history.root))

        let store = StorageFixtures.makeStore(
            root: history.root, safety: history.safety, knownLibraryID: history.libraryID, clock: history.clock)
        let load = try await store.load()
        #expect(load.library == history.versions[2])
        let report = try #require(load.recovery)
        #expect(safetyCopyName(report.source) != nil)
        #expect(report.damagedFileMovedTo == nil)
        let restored = try StorageFixtures.library(at: history.eventsFile)
        #expect(restored == history.versions[2])
    }

    @Test func missingEventsJSONIsRecoveredFromTheNewestBackup() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        try FileManager.default.removeItem(at: history.eventsFile)

        let store = StorageFixtures.makeStore(root: history.root, safety: folder.child("Other"), clock: history.clock)
        let load = try await store.load()
        #expect(load.library == history.versions[1])
        let report = try #require(load.recovery)
        #expect(backupName(report.source) == "events-20261006-125100.json")
        #expect(report.damagedFileMovedTo == nil)
        let restored = try StorageFixtures.library(at: history.eventsFile)
        #expect(restored == history.versions[1])
    }

    @Test func emptyFolderHasNoLibrary() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(root: root, safety: folder.child("Safety"), clock: clock)
        await #expect(throws: LibraryStoreError.noLibrary) {
            _ = try await store.load()
        }
        #expect(StorageFixtures.names(in: root).isEmpty)
    }

    @Test func missingEventsJSONWithoutBackupsHasNoLibrary() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        _ = try folder.makeDirectory("Library/.ithil/backups")
        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(
            root: root, safety: folder.child("Safety"), knownLibraryID: UUID(), clock: clock)
        await #expect(throws: LibraryStoreError.noLibrary) {
            _ = try await store.load()
        }
        #expect(StorageFixtures.names(in: StorageFixtures.metadataFolder(in: root)) == ["backups"])
    }

    @Test func missingFolderIsNeverRecreated() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let history = try await makeHistory(in: folder)
        let unplugged = folder.child("Unplugged")

        let store = StorageFixtures.makeStore(
            root: unplugged, safety: history.safety, knownLibraryID: history.libraryID, clock: history.clock)
        await #expect(throws: LibraryStoreError.noLibrary) {
            _ = try await store.load()
        }
        await #expect(throws: (any Error).self) {
            try await store.save(history.versions[2])
        }
        #expect(!StorageFixtures.exists(unplugged))
    }

    @Test func damagedFileWithNothingToRecoverFromIsLeftInPlace() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let metadata = StorageFixtures.metadataFolder(in: root)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true, attributes: nil)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: StorageFixtures.eventsFile(in: root))

        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(
            root: root, safety: folder.child("Safety"), knownLibraryID: UUID(), clock: clock)
        var caught: (any Error)?
        do {
            _ = try await store.load()
        } catch {
            caught = error
        }
        #expect(storageErrorIsUnreadable(caught))
        let after = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
        #expect(after == garbage)
        #expect(StorageFixtures.names(in: metadata) == ["events.json"])
    }

    // MARK: - Newer schema

    @Test func newerSchemaOpensReadOnlyAndIsNeverOverwritten() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        var library = StorageFixtures.sampleLibrary()
        let writer = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        try await writer.create(library)
        clock.advance(by: 60)
        try await writer.save(library)

        // A newer Ithil rewrote the file with schema version 2.
        let eventsFile = StorageFixtures.eventsFile(in: root)
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: eventsFile), options: [])
        var object = try #require(parsed as? [String: Any])
        object["schemaVersion"] = 2
        object["somethingNew"] = ["kind": "future"]
        let newer = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try newer.write(to: eventsFile)
        let backupsBefore = StorageFixtures.backupNames(in: root)
        let otherSafety = folder.child("OtherSafety")

        let store = StorageFixtures.makeStore(
            root: root, safety: otherSafety, knownLibraryID: library.id, clock: clock, backupInterval: 0)
        await #expect(throws: LibraryStoreError.newerSchema(found: 2, supported: 1)) {
            _ = try await store.load()
        }

        clock.advance(by: 2 * 60 * 60)
        library.events.removeAll()
        let changed = library
        await #expect(throws: LibraryStoreError.readOnly) {
            try await store.save(changed)
        }
        let after = try Data(contentsOf: eventsFile)
        #expect(after == newer)
        #expect(StorageFixtures.backupNames(in: root) == backupsBefore)
        #expect(StorageFixtures.names(in: StorageFixtures.metadataFolder(in: root)) == ["events.json", "backups"])
        #expect(!StorageFixtures.exists(otherSafety))
    }

    @Test func saveWithoutLoadNeverOverwritesANewerSchema() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let metadata = StorageFixtures.metadataFolder(in: root)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true, attributes: nil)
        let newer = Data(#"{"schemaVersion": 7, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#.utf8)
        try newer.write(to: StorageFixtures.eventsFile(in: root))

        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(root: root, safety: folder.child("Safety"), clock: clock)
        let library = StorageFixtures.sampleLibrary()
        await #expect(throws: LibraryStoreError.readOnly) {
            try await store.save(library)
        }
        await #expect(throws: LibraryStoreError.readOnly) {
            try await store.save(library)
        }
        let after = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
        #expect(after == newer)
        #expect(StorageFixtures.names(in: metadata) == ["events.json"])
        #expect(!StorageFixtures.exists(folder.child("Safety")))
    }

    @Test func saveAfterAFailedLoadSetsTheDamagedFileAside() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let metadata = StorageFixtures.metadataFolder(in: root)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true, attributes: nil)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: StorageFixtures.eventsFile(in: root))

        let clock = StorageTestClock(StorageFixtures.start)
        let store = StorageFixtures.makeStore(root: root, safety: folder.child("Safety"), clock: clock)
        var caught: (any Error)?
        do {
            _ = try await store.load()
        } catch {
            caught = error
        }
        #expect(storageErrorIsUnreadable(caught))

        let fresh = Library()
        try await store.save(fresh)
        let saved = try StorageFixtures.library(at: StorageFixtures.eventsFile(in: root))
        #expect(saved == fresh)
        let setAside = metadata.appending(component: "events.corrupt-20261006-115000.json")
        let setAsideData = try Data(contentsOf: setAside)
        #expect(setAsideData == garbage)
    }

    // MARK: - Failing disks

    @Test func failedWriteKeepsThePreviousFile() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        let original = StorageFixtures.sampleLibrary()
        try await StorageFixtures.makeStore(root: root, safety: safety, clock: clock).create(original)
        let before = try Data(contentsOf: StorageFixtures.eventsFile(in: root))

        let faulty = StorageFaultyFileSystem(failingWritesUnder: root)
        let store = StorageFixtures.makeStore(
            root: root, safety: safety, knownLibraryID: original.id, clock: clock, fileSystem: faulty)
        let opened = try await store.load()
        #expect(opened.library == original)
        clock.advance(by: 60)
        var changed = original
        changed.events.removeAll()
        let edited = changed
        await #expect(throws: (any Error).self) {
            try await store.save(edited)
        }

        let after = try Data(contentsOf: StorageFixtures.eventsFile(in: root))
        #expect(after == before)
        let reopened = StorageFixtures.makeStore(root: root, safety: safety, clock: clock)
        let load = try await reopened.load()
        #expect(load.library == original)
        #expect(load.recovery == nil)
    }

    @Test func failedSafetyCopyDoesNotFailTheSave() async throws {
        let folder = try StorageTempFolder()
        defer { folder.remove() }
        let root = try folder.makeDirectory("Library")
        let safety = folder.child("Safety")
        let clock = StorageTestClock(StorageFixtures.start)
        var library = StorageFixtures.sampleLibrary()
        let faulty = StorageFaultyFileSystem(failingWritesUnder: safety)
        let store = StorageFixtures.makeStore(root: root, safety: safety, clock: clock, fileSystem: faulty)

        try await store.create(library)
        clock.advance(by: 60)
        library.events.removeAll()
        try await store.save(library)

        let saved = try StorageFixtures.library(at: StorageFixtures.eventsFile(in: root))
        #expect(saved == library)
        #expect(StorageFixtures.names(in: safety).isEmpty)
    }
}
