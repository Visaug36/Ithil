import AppKit
import SwiftUI

/// The folder exists but holds no calendar, and there is no backup to restore one from.
struct NoLibraryView: View {
    let path: String
    @Environment(AppModel.self) private var model

    var body: some View {
        FolderSetupScreen(title: title, message: message, path: path) {
            Button("Start a New Calendar Here") {
                model.startFresh()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
            Button("Choose Another Folder…") {
                chooseAnotherFolder(model: model)
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: false))
        }
    }

    private var title: Text {
        Text("There's no calendar in this folder")
    }

    private var message: Text {
        Text("Ithil found no calendar file here, and no backup to restore one from.")
    }
}

/// The calendar file is damaged and couldn't be restored, or it is from a newer Ithil and can't be read.
/// The file is left untouched.
struct UnreadableLibraryView: View {
    let path: String
    let message: String
    @Environment(AppModel.self) private var model

    var body: some View {
        FolderSetupScreen(title: title, message: Text(verbatim: message), path: path.isEmpty ? nil : path) {
            Button("Try Again") {
                model.retryLoad()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
            Button("Choose Another Folder…") {
                chooseAnotherFolder(model: model)
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: false))
            if !path.isEmpty {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path, directoryHint: .isDirectory)])
                }
                .buttonStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Color.accentText)
                .padding(.top, 4)
            }
        }
    }

    private var title: Text {
        Text("Ithil can't open this calendar")
    }
}

@MainActor
private func chooseAnotherFolder(model: AppModel) {
    guard let url = FolderAccess.chooseExistingFolder() else { return }
    model.useFolder(url)
}

#Preview("No calendar") {
    NoLibraryView(path: "/Users/student/Documents/Ithil")
        .environment(AppModel.preview)
        .frame(width: 900, height: 620)
}

#Preview("Damaged") {
    UnreadableLibraryView(path: "/Users/student/Documents/Ithil", message: LibraryMessages.damaged)
        .environment(AppModel.preview)
        .frame(width: 900, height: 620)
}
