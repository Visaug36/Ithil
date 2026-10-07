import AppKit
import SwiftUI

/// Files: where the Ithil folder is, with Show in Finder and Change…, and how event folders are named.
///
/// Change… asks for a folder. An existing Ithil folder can be opened instead of the current one; any
/// other folder is where the calendar and its files can move to (into it when it is empty, else into a
/// new `Ithil` folder inside it), after asking. Not available in demo mode or for a read-only calendar.
struct FilesSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(FilesController.self) private var files
    @State private var prompt: FilesSettingsPrompt? = nil
    @State private var showsPrompt = false
    @State private var isCheckingFolder = false
    @State private var moveError = ""
    @State private var showsMoveError = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Ithil folder") {
                    FilesSettingsFolderLabel(root: model.rootURL)
                }
                buttonRow
            } footer: {
                Text("Each event gets its own folder, like 2026-10-06/14.00 Physics Lecture.")
                    .font(Typography.eventTime)
                    .foregroundStyle(Color.textTertiary)
            }
            if model.isDemo {
                Section {
                    FilesSettingsNote(
                        "Demo mode uses a temporary folder with sample data, so it can't be changed.",
                        "Your own calendar isn't touched.")
                }
            } else if model.isReadOnly {
                Section {
                    FilesSettingsNote(
                        "This calendar was saved by a newer version of Ithil, so it's read-only and can't be moved.",
                        "Update Ithil to make changes.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundWindow)
        .frame(height: 300)
        .modifier(
            FilesSettingsPromptAlert(
                prompt: prompt,
                isPresented: $showsPrompt,
                onOpen: { folder in files.openLibrary(at: folder) },
                onMove: { chosen in moveLibrary(to: chosen) }))
        .alert("Couldn't Move Your Calendar", isPresented: $showsMoveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveError)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            if files.isMovingLibrary {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Moving your calendar…")
                    .font(Typography.secondary)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("Show in Finder") {
                showInFinder()
            }
            .disabled(model.rootURL == nil)
            .accessibilityHint(Text("Shows your Ithil folder in Finder"))
            Button("Change…") {
                chooseFolder()
            }
            .disabled(!canChangeFolder)
            .accessibilityLabel(Text("Change Ithil Folder"))
            .accessibilityHint(Text("Moves your calendar to another folder, or opens another Ithil folder"))
        }
    }

    private var canChangeFolder: Bool {
        model.canEdit && !model.isDemo && model.rootURL != nil && !files.isMovingLibrary && !isCheckingFolder
    }

    private func showInFinder() {
        guard let root = model.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// Asks for a folder, then works out (off the main thread) what choosing it means.
    private func chooseFolder() {
        guard canChangeFolder, let current = model.rootURL else { return }
        guard let chosen = FilesSettingsPanel.chooseFolder(near: current) else { return }
        isCheckingFolder = true
        Task {
            let choice = await Task.detached(priority: .userInitiated) {
                LibraryFolderChoice.evaluate(chosen, currentRoot: current)
            }.value
            isCheckingFolder = false
            prompt = FilesSettingsPrompt(choice)
            showsPrompt = true
        }
    }

    private func moveLibrary(to chosen: URL) {
        Task {
            do {
                try await files.moveLibrary(to: chosen)
            } catch {
                moveError = FileMessages.libraryMoveFailed(error)
                showsMoveError = true
            }
        }
    }
}

/// Why Change… is off: two short sentences.
private struct FilesSettingsNote: View {
    let first: LocalizedStringKey
    let second: LocalizedStringKey

    init(_ first: LocalizedStringKey, _ second: LocalizedStringKey) {
        self.first = first
        self.second = second
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(first)
            Text(second)
        }
        .font(Typography.secondary)
        .foregroundStyle(Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// The folder row: a folder symbol and the path with the home folder as "~".
private struct FilesSettingsFolderLabel: View {
    let root: URL?

    var body: some View {
        if let root {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
                Text(FolderAccess.displayPath(root.path))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .help(root.path)
        } else {
            Text("No folder open")
                .foregroundStyle(Color.textTertiary)
        }
    }
}

/// What to ask after a folder was chosen in Settings → Files.
private enum FilesSettingsPrompt {
    /// The folder holds another Ithil calendar: open it instead?
    case open(URL)
    /// Move the calendar and its files there (into `newRoot`)?
    case move(chosen: URL, newRoot: URL)
    /// The folder can't be used; the sentence says why.
    case notice(String)

    init(_ choice: LibraryFolderChoice) {
        switch choice {
        case .currentLibrary:
            self = .notice(FileMessages.alreadyUsingFolder)
        case .insideCurrentLibrary:
            self = .notice(FileMessages.folderInsideLibrary)
        case .otherLibrary(let folder):
            self = .open(folder)
        case .move(let chosen, let newRoot):
            self = .move(chosen: chosen, newRoot: newRoot)
        case .unavailable:
            self = .notice(FileMessages.folderUnavailable)
        }
    }
}

/// The question (or notice) for the chosen folder, as an alert.
private struct FilesSettingsPromptAlert: ViewModifier {
    let prompt: FilesSettingsPrompt?
    @Binding var isPresented: Bool
    let onOpen: @MainActor (URL) -> Void
    let onMove: @MainActor (URL) -> Void

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented, presenting: prompt) { prompt in
                actions(for: prompt)
            } message: { prompt in
                message(for: prompt)
            }
    }

    private var title: Text {
        switch prompt {
        case .open(let folder):
            return Text("Open the calendar in “\(folder.lastPathComponent)”?")
        case .move(let chosen, _):
            return Text("Move your calendar and its files to “\(chosen.lastPathComponent)”?")
        case .notice, nil:
            return Text("Choose a Different Folder")
        }
    }

    @ViewBuilder private func actions(for prompt: FilesSettingsPrompt) -> some View {
        switch prompt {
        case .open(let folder):
            Button("Open That Calendar") {
                onOpen(folder)
            }
            Button("Cancel", role: .cancel) {}
        case .move(let chosen, _):
            Button("Move Everything") {
                onMove(chosen)
            }
            Button("Cancel", role: .cancel) {}
        case .notice:
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder private func message(for prompt: FilesSettingsPrompt) -> some View {
        switch prompt {
        case .open:
            Text("That folder already has an Ithil calendar. Your current one stays where it is.")
        case .move(_, let newRoot):
            moveMessage(newRoot)
        case .notice(let sentence):
            Text(sentence)
        }
    }

    /// Where everything goes; other files in the chosen folder stay as they are.
    private func moveMessage(_ newRoot: URL) -> Text {
        let path = FolderAccess.displayPath(newRoot.path)
        return Text("Everything moves to \(path). Other files there aren't touched.")
    }
}

/// The open panel for Change….
@MainActor
private enum FilesSettingsPanel {
    /// Asks for a folder to move the calendar to (or an Ithil folder to open), starting next to the
    /// current one.
    static func chooseFolder(near current: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a New Place for Ithil")
        panel.message = String(localized: "Choose a folder to move your calendar to, or another Ithil folder to open.")
        panel.prompt = String(localized: "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = current.deletingLastPathComponent()
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

#Preview {
    FilesSettingsView()
        .environment(AppModel.preview)
        .environment(FilesController.preview)
        .frame(width: 520)
}
