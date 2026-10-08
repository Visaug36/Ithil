import AppKit
import IthilCore

/// Sets up a `-demo` screenshot scene (see `DemoScene`) once the sample library is open: the appearance,
/// the view, the window size, the Physics Lecture selected as in the design, and optionally its details
/// popover or the Quick Add panel with sample text. Only ever created in demo mode.
@MainActor
final class DemoSceneDirector: LibraryChangeObserver {
    private let scene: DemoScene
    private weak var model: AppModel?
    private let settings: AppSettings
    private var didRun = false

    init(scene: DemoScene, model: AppModel, settings: AppSettings) {
        self.scene = scene
        self.model = model
        self.settings = settings
        if let span = scene.span {
            model.span = span
        }
        model.addChangeObserver(self)
        if let appearance = scene.appearance {
            // NSApp may not exist yet while the App is being initialized.
            Task { @MainActor in
                settings.appearance = appearance
            }
        }
    }

    func libraryDidChange(_ change: LibraryChange, from old: Library, to new: Library) {
        guard case .opened = change, !didRun else { return }
        didRun = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            await self?.run()
        }
    }

    private func run() async {
        guard let model else { return }
        await resizeMainWindow()
        let lecture = model.occurrences(on: model.today).first { $0.event.title == "Physics Lecture" }
        model.selectedOccurrenceID = lecture?.id
        switch scene.overlay {
        case .details:
            model.pendingDetailsOccurrenceID = lecture?.id
        case .quickAdd:
            QuickAddPanelController.shared.show(model: model, settings: settings, text: "physics quiz thursday 10am")
        case nil:
            break
        }
    }

    /// Waits up to 20 seconds for the main window (on a CI runner it can open late), then sizes and centers it.
    private func resizeMainWindow() async {
        guard let size = scene.windowSize else { return }
        for _ in 0..<80 {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }) {
                window.setContentSize(size)
                window.center()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
