import AppKit
import SwiftUI

/// One per document window. Owns the feature objects and is the single door to the
/// window's text view. Reach the key window's controller from menu commands with
/// `@FocusedValue(\.editorController)`.
@MainActor
@Observable
final class EditorController {
    /// The engine's text view. Nil until the editor is ready (a tick after the window opens).
    /// Its `string` is the raw Markdown, always fresh.
    @ObservationIgnored private(set) weak var textView: NSTextView?

    /// The document's file. Nil for an unsaved document; changes after Save As.
    var fileURL: URL?

    /// The document text as SwiftUI sees it. Observable, so views can react to edits.
    /// It trails the text view by one run-loop turn; use `currentText` for the exact value.
    var text: String = ""

    @ObservationIgnored private(set) lazy var lint = LintController(controller: self)
    @ObservationIgnored private(set) lazy var dropPaste = DropPasteHandler(controller: self)

    /// Exact text of the editor (the text view's string), or the document text before it exists.
    var currentText: String { textView?.string ?? text }

    /// Folder of the document, for resolving relative paths. Nil for an unsaved document.
    var documentFolder: URL? { fileURL?.deletingLastPathComponent() }

    var selectedRange: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }

    /// Called by ContentView when the engine has created the text view.
    func attach(_ textView: NSTextView) {
        self.textView = textView
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.window?.makeFirstResponder(textView)
        lint.install(on: textView)
    }

    /// Replace `range` as ONE undoable edit. Goes through shouldChangeText/didChangeText,
    /// so the engine restyles and updates the binding. False when the text view refuses.
    @discardableResult
    func replace(_ range: NSRange, with text: String, actionName: String? = nil) -> Bool {
        guard let textView, textView.shouldChangeText(in: range, replacementString: text),
              let storage = textView.textStorage
        else { return false }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        if let actionName { textView.undoManager?.setActionName(actionName) }
        return true
    }

    /// Explicit save (⌘S or File > Save with the editor focused): format, then run the real
    /// NSDocument save. Autosave and Save As do not come through here.
    /// Returns true: the engine's `save:` hook is fully handled.
    func saveRequested() -> Bool {
        formatForSave()
        // Next run-loop turn: the engine pushes the edited text into the document binding
        // asynchronously, and the save must see it.
        DispatchQueue.main.async { [weak self] in
            (self?.textView?.window?.windowController?.document as? NSDocument)?.save(nil)
        }
        return true
    }

    /// Move the selection; with `scroll` the range is scrolled into view.
    func setSelectedRange(_ range: NSRange, scroll: Bool = true) {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        let location = min(max(range.location, 0), length)
        let clamped = NSRange(location: location, length: min(max(range.length, 0), length - location))
        textView.setSelectedRange(clamped)
        if scroll { textView.scrollRangeToVisible(clamped) }
        textView.window?.makeFirstResponder(textView)
    }
}

private struct EditorControllerKey: FocusedValueKey {
    typealias Value = EditorController
}

extension FocusedValues {
    var editorController: EditorController? {
        get { self[EditorControllerKey.self] }
        set { self[EditorControllerKey.self] = newValue }
    }
}
