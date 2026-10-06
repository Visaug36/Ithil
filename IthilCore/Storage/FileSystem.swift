import Foundation

/// The file operations Ithil's storage and file handling need, behind a protocol so tests can use a
/// temporary folder or a double that fails on purpose.
///
/// URLs are file URLs. Methods that change the disk throw the underlying Foundation error.
public protocol FileSystem: Sendable {
    /// Whether anything (file, folder or link) exists at `url`.
    func fileExists(at url: URL) -> Bool
    /// Whether a folder exists at `url`.
    func isDirectory(at url: URL) -> Bool
    /// The items directly inside a folder, hidden files included, in no particular order.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    /// Creates a folder and any missing parents. Succeeds if the folder already exists.
    func createDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    /// Writes to a temporary file first and then renames it over `url`, so readers see either the old
    /// or the new contents, never a half-written file.
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Copies a file or folder. Fails if `destination` exists.
    func copyItem(at source: URL, to destination: URL) throws
    /// Moves or renames a file or folder. Fails if `destination` exists.
    func moveItem(at source: URL, to destination: URL) throws
    /// Deletes permanently. Only for Ithil's own housekeeping files (old backups); the user's files go
    /// to the Trash instead.
    func removeItem(at url: URL) throws
    /// Moves a file or folder to the Trash.
    func trashItem(at url: URL) throws
    /// When the item's contents last changed, or nil if it doesn't exist.
    func modificationDate(at url: URL) -> Date?
}

/// The real disk, through `FileManager.default`.
public struct LocalFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(at url: URL) -> Bool {
        var directoryFlag: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directoryFlag)
        return exists && directoryFlag.boolValue
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func trashItem(at url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public func modificationDate(at url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
}
