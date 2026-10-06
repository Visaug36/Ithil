import Foundation
import os

/// How far a `FileImport.copy` call has got.
///
/// Items are what was passed to `copy` (a folder counts as one item); bytes include everything inside
/// folders.
public struct FileCopyProgress: Hashable, Sendable {
    /// Bytes copied so far, across all items.
    public var completedBytes: Int64
    /// The size of all items together, measured before the first one is copied.
    public var totalBytes: Int64
    /// Items copied and in place under their final names.
    public var completedFiles: Int
    /// How many items `copy` was given.
    public var totalFiles: Int
    /// The original name of the item being copied; nil once every item is done.
    public var currentName: String?

    public init(
        completedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        completedFiles: Int = 0,
        totalFiles: Int = 0,
        currentName: String? = nil
    ) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentName = currentName
    }

    /// 0…1 by bytes; by items when there are no bytes to copy (only empty files); 0 when there is
    /// nothing to copy at all.
    public var fractionCompleted: Double {
        if totalBytes > 0 {
            return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
        }
        if totalFiles > 0 {
            return min(1, max(0, Double(completedFiles) / Double(totalFiles)))
        }
        return 0
    }
}

/// Copies the user's files into event folders.
///
/// Originals are never moved or changed. Each item is copied under a hidden temporary name and renamed
/// into place once it is complete, so neither Finder nor Ithil ever shows a half-copied file.
public enum FileImport {
    /// The start of the hidden name an item has while it is being copied (a UUID follows).
    static let temporaryNamePrefix = ".ithil-copying-"
    /// How often `copy` reports progress while one item is being copied.
    static let progressIntervalMilliseconds = 200
    /// The longest file name macOS volumes accept, in UTF-8 bytes.
    static let maximumNameBytes = 255

    private static var logger: Logger {
        Logger(subsystem: "io.github.visaug36.Ithil", category: "FileImport")
    }

    // MARK: - Names

    /// A name for `name` that is free in `folder`: `name` itself if nothing has it, else "notes 2.md",
    /// "notes 3.md"… like Finder. A name without an extension becomes "Photos 2" (an extension follows
    /// the last dot and has a letter and no spaces, so "Chapter 1.2" becomes "Chapter 1.2 2"). A name
    /// that already ends in a Finder number (2–999) continues it: "Report 2.pdf" becomes "Report 3.pdf".
    ///
    /// Ithil's own hidden names in event folders are never free: the `.ithil-event` marker's name
    /// becomes ".ithil-event 2", and a name starting like a temporary copy (".ithil-copying-") loses its
    /// dot.
    public static func availableName(for name: String, in folder: URL, fileSystem: any FileSystem) -> String {
        firstFreeName(for: name) { candidate in
            fileSystem.fileExists(at: folder.appending(component: candidate, directoryHint: .notDirectory))
        }
    }

    /// The first of `name`, "name 2", "name 3"… that isn't one of Ithil's own names and for which
    /// `isTaken` is false.
    static func firstFreeName(for name: String, isTaken: (String) -> Bool) -> String {
        // A name that looks like one of Ithil's temporary copies loses its leading dot, so nothing can ever
        // mistake the file for a leftover and clean it up.
        let name = name.lowercased().hasPrefix(temporaryNamePrefix) ? String(name.dropFirst()) : name
        if !isReserved(name) && !isTaken(name) {
            return name
        }
        let parts = FileImportNumberedName(name)
        let first = (parts.number ?? 1) + 1
        for number in first..<(first + 10_000) {
            let candidate = parts.name(withSuffix: String(number))
            if !isReserved(candidate) && !isTaken(candidate) {
                return candidate
            }
        }
        return parts.name(withSuffix: UUID().uuidString)
    }

    /// Whether `name` is one Ithil uses for its own hidden files in event folders (compared ignoring
    /// case, as macOS volumes usually do).
    static func isReserved(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased == EventFolderMarker.fileName.lowercased() || lowercased.hasPrefix(temporaryNamePrefix)
    }

    // MARK: - Copying

    /// Copies (never moves) `sources` into `folder`, one at a time, off the caller's thread, and returns
    /// the copies' URLs in the order of `sources`.
    ///
    /// Each item is copied to a hidden temporary name in `folder` (".ithil-copying-<uuid>") and renamed
    /// to `availableName(for:in:fileSystem:)` once complete, so a half-copied file never appears. On
    /// failure or cancellation the temporary item is removed, items already in place are kept, and the
    /// error (or `CancellationError`) is thrown. A copy can't be interrupted, so when the task is
    /// cancelled while an item is copying, that item is finished on disk, then removed.
    ///
    /// Uses `FileManager.copyItem` through `fileSystem`, which clones on APFS, so copies on the same
    /// volume are instant. `progress` is called on a background thread (keep it quick and hop to the
    /// main actor yourself): when each item starts, about every 0.2 s while one copies (measured from
    /// the temporary item's size; a folder counts every file in it), and once at the end with
    /// `currentName` nil. Reports never go backwards and end at `totalBytes`. No sources: returns []
    /// without reporting.
    ///
    /// Refuses, touching nothing, with `EventFoldersError.outsideRoot` when `folder` (after resolving
    /// `..` and symbolic links) isn't strictly inside `root`, and with `notADirectory` when it isn't an
    /// existing folder.
    public static func copy(
        _ sources: [URL],
        into folder: URL,
        root: URL,
        fileSystem: any FileSystem,
        progress: @escaping @Sendable (FileCopyProgress) -> Void
    ) async throws -> [URL] {
        let folder = folder.standardizedFileURL
        guard FileImportPathCheck.isStrictlyInside(folder, root: root) else {
            throw EventFoldersError.outsideRoot(folder.path)
        }
        guard fileSystem.isDirectory(at: folder) else {
            throw EventFoldersError.notADirectory(folder.path)
        }
        guard !sources.isEmpty else { return [] }
        try Task.checkCancellation()

        let items = sources.map(\.standardizedFileURL)
        let sizes = items.map { FileImportSizing.byteCount(of: $0) }
        var state = FileCopyProgress(totalBytes: sizes.reduce(0, +), totalFiles: items.count)
        var copied: [URL] = []
        for (index, source) in items.enumerated() {
            try Task.checkCancellation()
            state.currentName = source.lastPathComponent
            progress(state)
            let destination = try await copyOne(
                source, byteCount: sizes[index], into: folder, root: root, fileSystem: fileSystem, base: state,
                report: progress)
            copied.append(destination)
            state.completedBytes += sizes[index]
            state.completedFiles += 1
        }
        state.currentName = nil
        progress(state)
        return copied
    }

    /// Copies one item to a temporary name in `folder`, reporting its bytes on top of `base` while it
    /// runs, then renames it into place. Removes the temporary item on failure or cancellation.
    private static func copyOne(
        _ source: URL,
        byteCount: Int64,
        into folder: URL,
        root: URL,
        fileSystem: any FileSystem,
        base: FileCopyProgress,
        report: @Sendable (FileCopyProgress) -> Void
    ) async throws -> URL {
        let name = source.lastPathComponent
        guard isUsableName(name), !FileImportPathCheck.isInside(folder, root: source) else {
            // No name to give the copy, or a folder being copied into itself, which would never end.
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSURLErrorKey: source])
        }
        let temporaryName = temporaryNamePrefix + UUID().uuidString
        let temporary = folder.appending(component: temporaryName, directoryHint: .notDirectory)
        guard FileImportPathCheck.isStrictlyInside(temporary, root: root) else {
            throw EventFoldersError.outsideRoot(temporary.path)
        }

        let job = FileImportCopyJob()
        job.start { try fileSystem.copyItem(at: source, to: temporary) }
        var reportedBytes = base.completedBytes
        var outcome: FileImportCopyOutcome?
        while outcome == nil {
            outcome = await job.outcome(waitingUpToMilliseconds: progressIntervalMilliseconds)
            if outcome == nil && !Task.isCancelled {
                let copiedBytes = min(FileImportSizing.byteCount(of: temporary), byteCount)
                if base.completedBytes + copiedBytes > reportedBytes {
                    reportedBytes = base.completedBytes + copiedBytes
                    var update = base
                    update.completedBytes = reportedBytes
                    report(update)
                }
            }
        }

        do {
            try outcome?.get()
            try Task.checkCancellation()
            return try moveIntoPlace(temporary, as: name, in: folder, root: root, fileSystem: fileSystem)
        } catch {
            try? fileSystem.removeItem(at: temporary)
            if error is CancellationError {
                logger.notice("Stopped copying files: cancelled")
            } else {
                let reason = String(describing: error)
                logger.error("Could not copy \(name, privacy: .private): \(reason, privacy: .private)")
            }
            throw error
        }
    }

    /// Renames the finished temporary item to a free name, moving on to the next name if another copy
    /// took this one in the meantime.
    private static func moveIntoPlace(
        _ temporary: URL,
        as name: String,
        in folder: URL,
        root: URL,
        fileSystem: any FileSystem
    ) throws -> URL {
        let attempts = 5
        var claimed: Set<String> = []
        for attempt in 1...attempts {
            let finalName = firstFreeName(for: name) { candidate in
                claimed.contains(candidate) || itemExists(named: candidate, in: folder, fileSystem: fileSystem)
            }
            let destination = folder.appending(component: finalName, directoryHint: .notDirectory)
            guard FileImportPathCheck.isStrictlyInside(destination, root: root) else {
                throw EventFoldersError.outsideRoot(destination.path)
            }
            do {
                try fileSystem.moveItem(at: temporary, to: destination)
                return destination
            } catch {
                let nameWasTaken = itemExists(named: finalName, in: folder, fileSystem: fileSystem)
                guard nameWasTaken, attempt < attempts else { throw error }
                claimed.insert(finalName)
            }
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: folder])
    }

    /// Whether anything is at `name` in `folder`, a symbolic link whose target is missing included.
    private static func itemExists(named name: String, in folder: URL, fileSystem: any FileSystem) -> Bool {
        let url = folder.appending(component: name, directoryHint: .notDirectory)
        return fileSystem.fileExists(at: url) || FileImportSizing.anythingExists(at: url)
    }

    /// Whether `name` can be a file name in a folder: one path component, not "." or "..".
    private static func isUsableName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }
}

// MARK: - Helpers

/// A file name taken apart for numbering the way Finder does: "Report 2.pdf" is "Report", 2 and "pdf".
private struct FileImportNumberedName {
    /// The name without its extension and without its number.
    var base: String
    /// The Finder number already at the end of the name, if any.
    var number: Int?
    /// The extension without its dot, if any.
    var pathExtension: String?

    init(_ name: String) {
        var stem = name
        var pathExtension: String?
        // An extension follows the last dot, unless that dot starts the name (".gitignore"), or the part
        // after it has no letters ("Chapter 1.2") or has spaces in it ("Dr. Smith").
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let suffix = name[name.index(after: dot)...]
            let before = name[..<dot]
            let isExtension = suffix.contains(where: \.isLetter) && !suffix.contains(where: \.isWhitespace)
            if isExtension && before.contains(where: { $0 != "." }) {
                stem = String(before)
                pathExtension = String(suffix)
            }
        }
        var number: Int?
        if let space = stem.lastIndex(of: " "), space != stem.startIndex {
            if let value = Self.finderNumber(stem[stem.index(after: space)...]) {
                number = value
                stem = String(stem[..<space])
            }
        }
        self.base = stem
        self.number = number
        self.pathExtension = pathExtension
    }

    /// "base suffix.extension", with the base shortened if the name would be too long for a volume.
    func name(withSuffix suffix: String) -> String {
        let ending = pathExtension.map { " \(suffix).\($0)" } ?? " \(suffix)"
        var shortened = base
        while !shortened.isEmpty && (shortened + ending).utf8.count > FileImport.maximumNameBytes {
            shortened.removeLast()
        }
        return shortened + ending
    }

    /// The value of a number like the ones Finder adds: 2…999, plain digits, no leading zero. A year
    /// ("Report 2026") or "Track 01" isn't one.
    private static func finderNumber(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.count <= 3, text.first != "0" else { return nil }
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text) else { return nil }
        return value >= 2 ? value : nil
    }
}

private typealias FileImportCopyOutcome = Result<Void, any Error>

/// One copy running on a background queue (so blocking file work stays off Swift's cooperative
/// threads), and the copy task waiting for it with a timeout.
private final class FileImportCopyJob: @unchecked Sendable {
    private let lock = NSLock()
    private var finished: FileImportCopyOutcome?
    private var waiter: CheckedContinuation<FileImportCopyOutcome?, Never>?
    /// Counts waits, so a timer left over from an earlier wait can't end a later one.
    private var waitNumber = 0

    /// Runs `work` once on a background queue.
    func start(_ work: @escaping @Sendable () throws -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = FileImportCopyOutcome(catching: work)
            self.finish(with: outcome)
        }
    }

    /// The outcome once `work` has returned, or nil if `milliseconds` pass first.
    func outcome(waitingUpToMilliseconds milliseconds: Int) async -> FileImportCopyOutcome? {
        await withCheckedContinuation { continuation in
            install(continuation, milliseconds: milliseconds)
        }
    }

    private func install(_ continuation: CheckedContinuation<FileImportCopyOutcome?, Never>, milliseconds: Int) {
        lock.lock()
        if let finished {
            lock.unlock()
            continuation.resume(returning: finished)
            return
        }
        waitNumber += 1
        let number = waitNumber
        waiter = continuation
        lock.unlock()
        let deadline = DispatchTime.now() + .milliseconds(milliseconds)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
            self.endWait(number)
        }
    }

    private func finish(with outcome: FileImportCopyOutcome) {
        lock.lock()
        finished = outcome
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume(returning: outcome)
    }

    /// Ends wait `number` with nil if it is still the one waiting.
    private func endWait(_ number: Int) {
        lock.lock()
        guard number == waitNumber, let continuation = waiter else {
            lock.unlock()
            return
        }
        waiter = nil
        lock.unlock()
        continuation.resume(returning: nil)
    }
}

/// Whether a location stays inside a folder once `.`, `..` and symbolic links are resolved: the rule
/// `EventFolders.contains(_:)` applies, without needing the actor. Reads links through `FileManager`,
/// since `FileSystem` has no call for it.
enum FileImportPathCheck {
    /// Whether `url` is `root` itself or inside it.
    static func isInside(_ url: URL, root: URL) -> Bool {
        guard let rootComponents = resolvedComponents(of: root), let components = resolvedComponents(of: url) else {
            return false
        }
        return components.starts(with: rootComponents)
    }

    /// Whether `url` is inside `root` and not `root` itself: the only places Ithil writes to.
    static func isStrictlyInside(_ url: URL, root: URL) -> Bool {
        guard let rootComponents = resolvedComponents(of: root), let components = resolvedComponents(of: url) else {
            return false
        }
        return components.count > rootComponents.count && components.starts(with: rootComponents)
    }

    /// The absolute path of `url` as components, with `.` and `..` applied and every symbolic link in the
    /// existing part of the path resolved (components that don't exist are kept as written). Nil for a
    /// URL that isn't a file URL, or for a loop of links.
    static func resolvedComponents(of url: URL) -> [String]? {
        guard url.isFileURL else { return nil }
        var pending = Array(url.absoluteURL.path.split(separator: "/").map(String.init).reversed())
        var resolved: [String] = []
        var linksFollowed = 0
        while let component = pending.popLast() {
            if component == "." {
                continue
            }
            if component == ".." {
                if !resolved.isEmpty {
                    resolved.removeLast()
                }
                continue
            }
            let path = "/" + (resolved + [component]).joined(separator: "/")
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                resolved.append(component)
                continue
            }
            linksFollowed += 1
            guard linksFollowed <= 64 else { return nil }
            if destination.hasPrefix("/") {
                resolved.removeAll()
            }
            pending.append(contentsOf: destination.split(separator: "/").map(String.init).reversed())
        }
        return resolved
    }
}

/// Sizes and existence checks that `FileSystem` doesn't offer, read straight through `FileManager`.
enum FileImportSizing {
    /// The size of a file, or the total size of the regular files inside a folder (hidden files and
    /// package contents included). Symbolic links count as 0 and aren't followed; a missing item is 0.
    static func byteCount(of url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeRegular {
            return size(attributes)
        }
        guard type == .typeDirectory, let enumerator = FileManager.default.enumerator(atPath: url.path) else {
            return 0
        }
        var total: Int64 = 0
        while enumerator.nextObject() != nil {
            let entry = enumerator.fileAttributes ?? [:]
            if (entry[.type] as? FileAttributeType) == FileAttributeType.typeRegular {
                total += size(entry)
            }
        }
        return total
    }

    /// Whether anything is at `url`, without following a symbolic link there (a dangling link counts).
    static func anythingExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func size(_ attributes: [FileAttributeKey: Any]) -> Int64 {
        (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
