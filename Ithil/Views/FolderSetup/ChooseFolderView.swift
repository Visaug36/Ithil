import SwiftUI

/// First launch: where Ithil should keep the calendar and every event's files.
struct ChooseFolderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        FolderSetupScreen(title: title, message: message, footnote: footnote) {
            Button("Create Ithil Folder…") {
                createFolder()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: true))
            .keyboardShortcut(.defaultAction)
            Text("Suggested: \(FolderAccess.suggestedFolderDisplayPath)")
                .font(Typography.eventTime)
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, 6)
            Button("Use Existing Folder…") {
                chooseFolder()
            }
            .buttonStyle(FolderSetupButtonStyle(isProminent: false))
        }
    }

    private var title: Text {
        Text("Choose where Ithil keeps your calendar")
    }

    private var message: Text {
        Text("Every event gets its own folder there, so its files are real files you can also open in Finder.")
    }

    private var footnote: Text {
        Text("Copy the folder to back up everything, or open it on another Mac to pick up where you left off.")
    }

    private func createFolder() {
        guard let url = FolderAccess.createFolder() else { return }
        model.useFolder(url)
    }

    private func chooseFolder() {
        guard let url = FolderAccess.chooseExistingFolder() else { return }
        model.useFolder(url)
    }
}

#Preview {
    ChooseFolderView()
        .environment(AppModel.preview)
        .frame(width: 900, height: 620)
}
