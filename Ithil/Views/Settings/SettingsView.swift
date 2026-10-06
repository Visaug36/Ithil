import SwiftUI

/// The Settings window: General, Subjects and Files tabs.
///
/// Launch at login, the menu bar extra and the Quick Add hotkey join General in a later phase; changing
/// and moving the folder joins Files.
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
}
