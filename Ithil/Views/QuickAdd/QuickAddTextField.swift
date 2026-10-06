import AppKit
import SwiftUI

/// Quick Add's single-line input, about 17 pt. The date and time Quick Add recognized are highlighted in
/// place (`AccentSoft` behind, `AccentText` letters) with the layout manager's temporary attributes, so
/// the text itself never changes.
///
/// Return calls `onSubmit` and Escape `onCancel`; ⌘Return is handled by `QuickAddPanel`. The field takes
/// keyboard focus as soon as it is in a window. In the Quick Add panel it edits with a TextKit 1 field
/// editor (`QuickAddInputField.makeFieldEditor()`), which has the layout manager the highlights need.
struct QuickAddTextField: NSViewRepresentable {
    @Binding var text: String
    let highlightedRanges: [NSRange]
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> QuickAddInputField {
        let field = QuickAddInputField(frame: .zero)
        let font = NSFont.systemFont(ofSize: 17)
        field.font = font
        field.textColor = NSColor(resource: .textPrimary)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        let placeholderAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(resource: .textTertiary),
        ]
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: placeholderAttributes)
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityLabel(String(localized: "Quick Add"))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: QuickAddInputField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.applyHighlights(highlightedRanges, to: field)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: QuickAddInputField, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        return CGSize(width: width, height: field.intrinsicContentSize.height.rounded(.up))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickAddTextField
        private var highlightedText = ""
        private var highlighted: [NSRange] = []

        init(parent: QuickAddTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }

        /// Marks `ranges` (UTF-16, as `QuickAddDraft.highlightedRanges`) in the field editor. Only while
        /// the field is being edited, which in the panel is always.
        func applyHighlights(_ ranges: [NSRange], to field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView, let layoutManager = editor.layoutManager else {
                return
            }
            let text = editor.string
            guard text != highlightedText || ranges != highlighted else { return }
            highlightedText = text
            highlighted = ranges
            let length = (text as NSString).length
            let everything = NSRange(location: 0, length: length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: everything)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: everything)
            let attributes: [NSAttributedString.Key: Any] = [
                .backgroundColor: NSColor(resource: .accentSoft),
                .foregroundColor: NSColor(resource: .accentText),
            ]
            for range in ranges where range.location != NSNotFound && NSMaxRange(range) <= length {
                layoutManager.addTemporaryAttributes(attributes, forCharacterRange: range)
            }
        }
    }
}

/// The text field behind `QuickAddTextField`. `QuickAddPanel` gives it its own field editor.
final class QuickAddInputField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// A TextKit 1 field editor, so highlights can use `NSLayoutManager` temporary attributes.
    static func makeFieldEditor() -> NSTextView {
        let editor = NSTextView(usingTextLayoutManager: false)
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.insertionPointColor = NSColor(resource: .accentText)
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        return editor
    }
}
