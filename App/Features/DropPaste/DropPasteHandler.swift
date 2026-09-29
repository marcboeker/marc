import AppKit
import Demark

/// Connected to the engine's paste and drop hooks in ContentView.
/// Returning false leaves the engine's default behavior in place.
@MainActor
final class DropPasteHandler {
    private unowned let controller: EditorController
    private lazy var demark = Demark()

    init(controller: EditorController) {
        self.controller = controller
    }

    /// Called before ⌘V. Return true if handled. Not called for ⌥⇧⌘V.
    func willPaste(in textView: NSTextView, pasteboard: NSPasteboard) -> Bool {
        guard let html = pasteboard.string(forType: .html), !html.isEmpty else { return false }
        let plain = pasteboard.string(forType: .string)
        let range = textView.selectedRange()

        if PastePolicy.prefersPlainText(html: html, plain: plain), let plain {
            insert(plain, replacing: range, in: textView)
            return true
        }

        let before = textView.string
        Task { [weak self, weak textView] in
            guard let self else { return }
            let converted = try? await demark.convertToMarkdown(html)
            guard let textView else { return }
            let markdown = converted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = markdown.isEmpty ? (plain ?? "") : markdown
            guard !text.isEmpty else { return }
            // An edit during the conversion makes the captured range stale: use the current selection.
            let target = textView.string == before ? range : textView.selectedRange()
            insert(text, replacing: target, in: textView)
        }
        return true
    }

    /// Called when file URLs are dropped. `insertionIndex` is a UTF-16 index in `textView.string`.
    func drop(in textView: NSTextView, info: NSDraggingInfo, insertionIndex: Int) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else { return false }
        let markdown = LinkBuilder.markdown(for: urls, documentFolder: controller.documentFolder)
        let index = min(max(insertionIndex, 0), (textView.string as NSString).length)
        insert(markdown, replacing: NSRange(location: index, length: 0), in: textView)
        return true
    }

    /// Undo-safe replace; the cursor ends after the inserted text.
    private func insert(_ text: String, replacing range: NSRange, in textView: NSTextView) {
        guard controller.replace(range, with: text) else { return }
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }
}
