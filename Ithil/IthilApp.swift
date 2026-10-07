import SwiftUI

/// Ithil's scenes: the main window and Settings, sharing one `AppModel`, one `AppSettings`, one
/// `FilesController` and one `NotificationsController`.
///
/// All four are created once, here, from the launch arguments (`-demo` gives them a temporary folder and
/// throwaway settings), and injected with `.environment`. The controllers are created before
/// `model.start()`, so they are registered as library observers before any library opens.
@main
struct IthilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var model: AppModel
    @State private var files: FilesController
    @State private var notifications: NotificationsController

    init() {
        let options = LaunchOptions.current
        let defaults = options.isDemo ? LaunchOptions.makeDemoDefaults() : UserDefaults.standard
        let settings = AppSettings(defaults: defaults)
        let model = AppModel(options: options, settings: settings, defaults: defaults)
        let files = FilesController(model: model)
        let notifications = NotificationsController(model: model, files: files)
        model.start()
        _settings = State(initialValue: settings)
        _model = State(initialValue: model)
        _files = State(initialValue: files)
        _notifications = State(initialValue: notifications)
        // Before the first window draws, where possible; `connect()` makes sure of it.
        Task { @MainActor in
            Appearance.apply(settings.appearance)
        }
    }

    var body: some Scene {
        WindowGroup(id: MainView.windowID) {
            MainView()
                .environment(model)
                .environment(settings)
                .environment(files)
                .environment(notifications)
                .onAppear { connect() }
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            IthilCommands(model: model, settings: settings)
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(settings)
                .environment(files)
                .environment(notifications)
                .onAppear { connect() }
        }
    }

    /// Hands the model to the app delegate (for quitting safely) and applies the appearance setting.
    private func connect() {
        appDelegate.model = model
        Appearance.apply(settings.appearance)
    }
}
