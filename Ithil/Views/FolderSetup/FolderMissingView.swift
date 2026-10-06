import SwiftUI

/// The saved folder can't be found: moved, renamed, deleted, or on a drive that isn't connected.
///
/// The user can point Ithil at it again, try again after reconnecting a drive, or choose another
/// folder. Ithil never offers to start an empty calendar from here.
struct FolderMissingView: View {
    let path: String
    @Environment(AppModel.self) private var model

    var body: some View {
        FolderSetupScreen(title: title, message: message, path: path.isEmpty ? nil : path, footnote: footnote) {
            Button("Locate Folder…") {
                locateFolder()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
            Button("Choose Another Folder…") {
                chooseAnotherFolder()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: false))
            Button("Try Again") {
                model.retryLoad()
            }
            .buttonStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Color.accentText)
            .padding(.top, 4)
        }
    }

    private var title: Text {
        Text("Ithil can't find its folder")
    }

    private var message: Text {
        Text("It may have been moved, renamed or deleted, or it's on a drive that isn't connected.")
    }

    private var footnote: Text {
        Text("If it's on an external drive, connect the drive and choose Try Again.")
    }

    private func locateFolder() {
        guard let url = FolderAccess.locateFolder(lastKnownPath: path) else { return }
        model.relocateFolder(url)
    }

    private func chooseAnotherFolder() {
        guard let url = FolderAccess.chooseExistingFolder() else { return }
        model.useFolder(url)
    }
}

#Preview {
    FolderMissingView(path: "/Users/student/Documents/Ithil")
        .environment(AppModel.preview)
        .frame(width: 900, height: 620)
}
