import IthilCore
import SwiftUI

/// The main window's content: one screen per `LibraryState`, plus the alerts for a recovered library,
/// a failed save and a folder that can't be used.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .frame(minWidth: 720, minHeight: 480)
            .modifier(RecoveryAlert())
            .modifier(SaveErrorAlert())
            .modifier(FolderErrorAlert())
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .needsFolder:
            ChooseFolderView()
        case .loading:
            LoadingView()
        case .ready:
            CalendarWindow()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.isReadOnly {
                        ReadOnlyBanner()
                    }
                }
        case .folderMissing(let path):
            FolderMissingView(path: path)
        case .noLibrary(let path):
            NoLibraryView(path: path)
        case .unreadable(let path, let message):
            UnreadableLibraryView(path: path, message: message)
        }
    }
}

/// A quiet spinner while the library opens. It only appears after a moment, so a fast launch doesn't
/// flash it.
private struct LoadingView: View {
    @State private var showsSpinner = false

    var body: some View {
        ZStack {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Opening your calendar"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundWindow)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(400))
                showsSpinner = true
            } catch {}
        }
    }
}

/// A slim strip along the bottom of the window while the library is read-only.
private struct ReadOnlyBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.accentText)
                .accessibilityHidden(true)
            Text("Read-only: this calendar was saved by a newer version of Ithil. Update Ithil to make changes.")
                .font(Typography.secondary)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSidebar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.separatorLine)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecoveryAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var alerts = model
        let report = model.recoveryNotice
        let isPresented = $alerts.showsRecoveryNotice
        content.alert("Ithil restored your calendar", isPresented: isPresented, presenting: report) { _ in
            Button("OK") {}
        } message: { report in
            Text(verbatim: LibraryMessages.recovery(report))
        }
    }
}

private struct SaveErrorAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var alerts = model
        let message = model.saveError
        let isPresented = $alerts.showsSaveError
        content.alert("Ithil couldn't save your changes", isPresented: isPresented, presenting: message) { _ in
            Button("Try Again") { model.retrySave() }
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(verbatim: message)
        }
    }
}

private struct FolderErrorAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var alerts = model
        let message = model.folderError
        let isPresented = $alerts.showsFolderError
        content.alert("Ithil can't use that folder", isPresented: isPresented, presenting: message) { _ in
            Button("OK") {}
        } message: { message in
            Text(verbatim: message)
        }
    }
}
