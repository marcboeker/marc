//  Marcdown: file URL drops. NSTextView (rich text) would embed a file attachment;
//  instead the embedder's `onDropFiles` decides what text to insert.

import AppKit

extension NativeTextView {
    // Marcdown: add `.fileURL` to whatever NSTextView already accepts.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        var types = super.acceptableDragTypes
        if onDropFiles != nil, !types.contains(.fileURL) { types.append(.fileURL) }
        return types
    }

    /// Re-register drag types after `onDropFiles` is set.
    func refreshDragTypes() {
        unregisterDraggedTypes()
        registerForDraggedTypes(acceptableDragTypes)
    }

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        onDropFiles != nil && sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingEntered(sender)
        return op.isEmpty && hasFileURLs(sender) ? .copy : op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingUpdated(sender)
        return op.isEmpty && hasFileURLs(sender) ? .copy : op
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isEditable, hasFileURLs(sender), let hook = onDropFiles {
            let point = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: point)
            if hook(self, sender, index) { return true }
        }
        return super.performDragOperation(sender)
    }
}
