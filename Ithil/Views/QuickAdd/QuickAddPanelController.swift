import AppKit
import SwiftUI

/// Shows and hides the Quick Add panel (⌘N in the app; later also the global hotkey).
///
/// The panel floats above every app and space without activating Ithil, so typing there doesn't pull the
/// user out of what they were doing. Each `show` starts from empty text with the field focused, centered
/// horizontally in the upper part of the screen the pointer is on. It closes on Return (after adding),
/// Escape, or a click elsewhere; when Ithil was active, its previous window gets the keyboard back.
@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()

    private var panel: QuickAddPanel?
    private var session: QuickAddSession?
    /// Ithil's key window when the panel opened, to give the keyboard back to on close.
    private weak var previousKeyWindow: NSWindow?
    private var isClosing = false

    private init() {}

    var isShown: Bool {
        panel?.isVisible ?? false
    }

    func toggle(model: AppModel, settings: AppSettings) {
        if isShown {
            close()
        } else {
            show(model: model, settings: settings)
        }
    }

    /// Shows the panel, centered in the upper third of the active screen. `text` pre-fills the field
    /// (used by `-demo` screenshot scenes).
    func show(model: AppModel, settings: AppSettings, text: String = "") {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let app = NSApplication.shared
        if app.isActive, let keyWindow = app.keyWindow, keyWindow !== panel {
            previousKeyWindow = keyWindow
        }
        let session = QuickAddSession(
            model: model,
            onClose: { [weak self] in
                self?.close()
            },
            onReveal: { [weak self] in
                self?.revealMainWindow()
            })
        session.text = text
        self.session = session
        panel.onCommandReturn = { [weak session] in
            session?.submit(openingEditor: true)
        }
        let hostingView = NSHostingView(rootView: QuickAddRoot(session: session, model: model, settings: settings))
        // Ends any editing in the previous content (⌘N while the panel is already open) before replacing it.
        panel.makeFirstResponder(nil)
        panel.contentView = hostingView
        let size = hostingView.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func close() {
        close(restoringFocus: true)
    }

    // MARK: - Private

    private func close(restoringFocus: Bool) {
        guard !isClosing, let panel, panel.isVisible else { return }
        isClosing = true
        panel.orderOut(nil)
        isClosing = false
        session = nil
        let previous = previousKeyWindow
        previousKeyWindow = nil
        if restoringFocus, NSApplication.shared.isActive, let previous, previous.isVisible {
            previous.makeKeyAndOrderFront(nil)
        }
    }

    /// After ⌘Return: hides the panel, activates Ithil and brings its main window forward, where the
    /// calendar opens the new event's editor.
    private func revealMainWindow() {
        close(restoringFocus: false)
        let app = NSApplication.shared
        app.activate()
        let windows = app.windows.filter { window in
            !(window is NSPanel) && window.canBecomeMain && (window.isVisible || window.isMiniaturized)
        }
        guard let window = windows.first(where: { !Self.isSettingsWindow($0) }) ?? windows.first else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false
    }

    /// Centered horizontally, a quarter of the way down the visible part of the screen with the pointer.
    private func origin(for size: NSSize) -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        let x = visible.midX - size.width / 2
        let centerY = visible.maxY - visible.height / 4
        let y = min(visible.maxY - size.height, centerY - size.height / 2)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    private func makePanel() -> QuickAddPanel {
        let panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: true)
        panel.title = String(localized: "Quick Add")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in
            self?.close()
        }
        panel.onResignKey = { [weak self] in
            self?.close()
        }
        return panel
    }
}

/// The Quick Add window: a floating panel that takes the keyboard without activating Ithil.
///
/// It can become key (borderless-looking panels otherwise can't), closes on Escape, reports ⌘Return
/// (which reaches it as a key equivalent before the text field sees it), and gives the Quick Add field a
/// TextKit 1 field editor so its highlights work.
final class QuickAddPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onCommandReturn: (() -> Void)?
    var onResignKey: (() -> Void)?
    private var inputEditor: NSTextView?

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCommandReturn(event), let onCommandReturn {
            onCommandReturn()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        guard object is QuickAddInputField else {
            return super.fieldEditor(createFlag, for: object)
        }
        if let inputEditor {
            return inputEditor
        }
        guard createFlag else { return nil }
        let editor = QuickAddInputField.makeFieldEditor()
        inputEditor = editor
        return editor
    }

    private static func isCommandReturn(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let returnKey: UInt16 = 36
        let enterKey: UInt16 = 76
        return modifiers == .command && (event.keyCode == returnKey || event.keyCode == enterKey)
    }
}

/// The panel's SwiftUI root: the view with the app's model and settings, edge to edge under the hidden
/// title bar.
private struct QuickAddRoot: View {
    let session: QuickAddSession
    let model: AppModel
    let settings: AppSettings

    var body: some View {
        QuickAddView(session: session)
            .environment(model)
            .environment(settings)
            .ignoresSafeArea()
    }
}
