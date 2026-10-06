import Foundation
import IthilCore

/// The user-facing explanations `AppModel` puts in its states and alerts. Technical details go to the
/// log, never here. Each sentence is its own localized string.
enum LibraryMessages {
    // MARK: - Opening

    static var damaged: String {
        joined(
            String(localized: "The calendar file is damaged, and there's no backup Ithil can restore it from."),
            String(localized: "Ithil left the file as it was."))
    }

    static var newerVersion: String {
        joined(
            String(localized: "This calendar was saved by a newer version of Ithil."),
            String(localized: "Update Ithil to open it."))
    }

    static func couldNotOpen(_ error: any Error) -> String {
        joined(String(localized: "Ithil couldn't open the calendar in this folder."), error.localizedDescription)
    }

    static func couldNotCreate(_ error: any Error) -> String {
        joined(String(localized: "Ithil couldn't create a calendar in this folder."), error.localizedDescription)
    }

    static func couldNotSetUpDemo(_ error: any Error) -> String {
        joined(String(localized: "Ithil couldn't set up the demo folder."), error.localizedDescription)
    }

    // MARK: - Choosing a folder

    static func cannotUseFolder(_ error: any Error) -> String {
        if (error as? FolderAccess.SetupError) == .noCalendarFound {
            return joined(
                String(localized: "That folder doesn't have an Ithil calendar in it."),
                String(localized: "To start a new calendar elsewhere, use Choose Another Folder instead."))
        }
        return error.localizedDescription
    }

    static var demoCannotChangeFolder: String {
        String(localized: "The demo uses a temporary folder, so it can't switch to another one.")
    }

    // MARK: - Saving

    static func saveFailed(_ error: any Error) -> String {
        if (error as? LibraryStoreError) == .readOnly {
            return joined(
                String(localized: "This calendar was saved by a newer version of Ithil."),
                String(localized: "This version of Ithil won't change it."))
        }
        if (error as? CocoaError)?.code == .fileNoSuchFile {
            return joined(
                String(localized: "Ithil can't find its folder. Your changes are still open in Ithil."),
                String(localized: "Reconnect the drive or put the folder back, then try again."))
        }
        return joined(String(localized: "Ithil couldn't save your latest changes."), error.localizedDescription)
    }

    // MARK: - Recovery

    /// What happened and what Ithil did, for the "Ithil restored your calendar" alert.
    static func recovery(_ report: RecoveryReport) -> String {
        var sentences: [String] = []
        if report.damagedFileMovedTo != nil {
            sentences.append(String(localized: "Your calendar file was damaged."))
        } else {
            sentences.append(String(localized: "Your calendar file was missing."))
        }
        let savedText = report.recoveredSavedAt?.formatted(date: .long, time: .shortened)
        switch (report.source, savedText) {
        case (.backup, let savedAt?):
            sentences.append(String(localized: "Ithil restored the backup saved \(savedAt)."))
            sentences.append(String(localized: "Changes made after that may be missing."))
        case (.backup, nil):
            sentences.append(String(localized: "Ithil restored its newest backup."))
            sentences.append(String(localized: "Changes made after that may be missing."))
        case (.safetyCopy, let savedAt?):
            sentences.append(
                String(localized: "Ithil restored the safety copy it keeps on this Mac, saved \(savedAt)."))
        case (.safetyCopy, nil):
            sentences.append(String(localized: "Ithil restored the safety copy it keeps on this Mac."))
        }
        if let damaged = report.damagedFileMovedTo {
            let path = FolderAccess.displayPath(damaged.path)
            sentences.append(String(localized: "The damaged file was kept at \(path)."))
        }
        return sentences.joined(separator: " ")
    }

    private static func joined(_ sentences: String...) -> String {
        sentences.joined(separator: " ")
    }
}
