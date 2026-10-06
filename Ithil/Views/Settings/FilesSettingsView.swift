import AppKit
import SwiftUI

/// Files: where the Ithil folder is, with Show in Finder, and how event folders are named.
///
/// Changing the folder (and moving everything there) arrives with the files phase.
struct FilesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Ithil folder") {
                    folderLabel
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        showInFinder()
                    }
                    .disabled(model.rootURL == nil)
                }
            } footer: {
                Text("Each event gets its own folder, like 2026-10-06/14.00 Physics Lecture.")
                    .font(Typography.eventTime)
                    .foregroundStyle(Color.textTertiary)
            }
            if model.isDemo {
                Section {
                    Text("Demo mode: this is a temporary folder with sample data. Your own calendar isn't touched.")
                        .font(Typography.secondary)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundWindow)
        .frame(height: 260)
    }

    @ViewBuilder private var folderLabel: some View {
        if let root = model.rootURL {
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

    private func showInFinder() {
        guard let root = model.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}
