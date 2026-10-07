import SwiftUI

/// The Settings window: General, Subjects and Files tabs.
///
/// General also shows the notification permission; Files changes or moves the folder. Launch at login, the
/// menu bar extra and the Quick Add hotkey join General in a later phase.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            SubjectsSettingsView()
                .tabItem {
                    Label("Subjects", systemImage: "circle.grid.2x2")
                }
            FilesSettingsView()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
        }
        .frame(width: 520)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.preview)
        .environment(AppSettings.preview)
        .environment(FilesController.preview)
        .environment(NotificationsController.preview)
}
