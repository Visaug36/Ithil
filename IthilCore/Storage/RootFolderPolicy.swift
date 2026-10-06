import Foundation

/// Decides which folder becomes the library root when the user picks one.
///
/// An empty folder or an existing Ithil folder is used as is. Any other folder gets an `Ithil`
/// subfolder, or `Ithil 2`, `Ithil 3`… if that name is already taken by something else, so Ithil never
/// mixes its files into a folder full of the user's own.
public enum RootFolderPolicy {
    /// The name of the folder Ithil suggests (in Documents) and creates inside a non-empty folder.
    public static let defaultFolderName = "Ithil"

    /// Whether `url` is a library root: it contains a `.ithil` folder. Its events.json may be missing
    /// or damaged; `LibraryStore.load()` then recovers it from a backup.
    public static func isIthilFolder(_ url: URL, fileSystem: any FileSystem) -> Bool {
        let metadataFolder = url.appending(component: LibraryStore.metadataFolderName, directoryHint: .isDirectory)
        return fileSystem.isDirectory(at: metadataFolder)
    }

    /// Whether `url` is a folder with nothing in it but Finder and volume metadata (`.DS_Store`,
    /// `.localized`, a custom-icon `Icon\r` file, `._` AppleDouble files, Spotlight and Trash folders
    /// at the root of a drive). False for a missing folder or a file.
    public static func isEffectivelyEmpty(_ url: URL, fileSystem: any FileSystem) -> Bool {
        guard fileSystem.isDirectory(at: url) else { return false }
        guard let contents = try? fileSystem.contentsOfDirectory(at: url) else { return false }
        return contents.allSatisfy { isMetadataItem(named: $0.lastPathComponent) }
    }

    /// The library root to use for a folder the user chose: `url` itself when it is empty or already an
    /// Ithil folder, otherwise its `Ithil` subfolder (created if needed; `Ithil 2`… when `Ithil` exists
    /// and is neither empty nor an Ithil folder).
    ///
    /// Creates at most that one folder and writes nothing else. Throws if `url` is not an existing
    /// folder or the subfolder can't be created.
    public static func libraryFolder(forChosen url: URL, fileSystem: any FileSystem) throws -> URL {
        guard fileSystem.isDirectory(at: url) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: url])
        }
        if isUsableAsIs(url, fileSystem: fileSystem) {
            return url
        }
        for number in 1...999 {
            let name = number == 1 ? defaultFolderName : "\(defaultFolderName) \(number)"
            let candidate = url.appending(component: name, directoryHint: .isDirectory)
            if !fileSystem.fileExists(at: candidate) {
                try fileSystem.createDirectory(at: candidate)
                return candidate
            }
            if isUsableAsIs(candidate, fileSystem: fileSystem) {
                return candidate
            }
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: url])
    }

    private static func isUsableAsIs(_ url: URL, fileSystem: any FileSystem) -> Bool {
        isIthilFolder(url, fileSystem: fileSystem) || isEffectivelyEmpty(url, fileSystem: fileSystem)
    }

    private static func isMetadataItem(named name: String) -> Bool {
        ignoredMetadataNames.contains(name) || name.hasPrefix("._")
    }

    /// Items macOS creates on its own in folders and at the root of drives.
    private static let ignoredMetadataNames: Set<String> = [
        ".DS_Store",
        ".localized",
        "Icon\r",
        ".fseventsd",
        ".Spotlight-V100",
        ".Trashes",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
        ".VolumeIcon.icns",
        ".com.apple.timemachine.donotpresent",
    ]
}
