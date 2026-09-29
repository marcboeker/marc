import Foundation

extension EditorController {
    /// Format the buffer before an explicit ⌘S (never called for autosave).
    /// One undo step that replaces only the changed range. The cursor keeps its line and column.
    func formatForSave() {
        let old = currentText
        let formatted = MarkdownFormatting.format(old)
        let location = MarkdownFormatting.mapLocation(selectedRange.location, from: old, to: formatted)
        guard let change = MarkdownEdits.replacement(from: old, to: formatted),
              replace(change.range, with: change.text, actionName: "Format")
        else { return }
        setSelectedRange(NSRange(location: location, length: 0), scroll: false)
    }
}
