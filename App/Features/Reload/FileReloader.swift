import AppKit

/// Reloads the editor when another process changes the document's file.
/// SwiftUI's `DocumentGroup` does not do this; its NSDocument keeps the old text and a later save overwrites the outside change.
/// A clean buffer is replaced quietly (undo history cleared, cursor kept). A buffer with unsaved edits asks first:
/// merge, keep the edits, or reload.
@MainActor
final class FileReloader: NSObject, NSFilePresenter {
    nonisolated let presentedItemOperationQueue = OperationQueue.main
    nonisolated(unsafe) private var url: URL?
    nonisolated var presentedItemURL: URL? { url }

    private weak var controller: EditorController?
    /// The file's text when we last read or wrote it. A buffer equal to this has no unsaved edits.
    private var lastKnownDisk = ""
    private var isAsking = false

    init(controller: EditorController) {
        self.controller = controller
    }

    /// Start (or move) watching. `text` is what the file holds right now.
    func watch(_ url: URL?, text: String) {
        lastKnownDisk = text
        guard url != self.url else { return }
        stop()
        guard let url else { return }
        self.url = url
        NSFileCoordinator.addFilePresenter(self)
    }

    /// The file coordinator retains its presenters, so this must run when the window closes.
    func stop() {
        guard url != nil else { return }
        NSFileCoordinator.removeFilePresenter(self)
        url = nil
    }

    nonisolated func presentedItemDidChange() {
        MainActor.assumeIsolated { fileChanged() }
    }

    private func fileChanged() {
        guard let controller, let url else { return }
        // Date first: if the file changes between the two reads, the date is the older one and NSDocument still warns.
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let data = try? Data(contentsOf: url),        // gone or mid-save: keep the old text, the next change retries
              let disk = String(data: data, encoding: .utf8)
        else { return }
        switch ReloadPolicy.action(disk: disk, buffer: controller.currentText, lastKnownDisk: lastKnownDisk) {
        case .ignore: lastKnownDisk = disk
        case .reload: reload(disk, modified: modified)
        case .ask: ask(disk, modified: modified)
        }
    }

    private func reload(_ disk: String, modified: Date?) {
        guard let controller, let textView = controller.textView else { return }
        let selection = controller.selectedRange
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        guard controller.replace(whole, with: disk) else { return }
        controller.setSelectedRange(selection, scroll: false)   // clamped to the new length
        textView.undoManager?.removeAllActions()
        accept(disk, modified: modified)
        // The engine pushes the text into the document binding a turn later; clear the edited mark after that.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { self?.document?.updateChangeCount(.changeCleared) }
        }
    }

    /// Merge the outside change into the buffer as one undoable edit. The buffer stays unsaved, so the user checks it first.
    private func merge(_ disk: String, modified: Date?) {
        guard let controller, let textView = controller.textView else { return }
        let result = Merge.merge(base: lastKnownDisk, mine: controller.currentText, theirs: disk)
        let selection = controller.selectedRange
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        guard controller.replace(whole, with: result.text, actionName: "Merge") else { return }
        controller.setSelectedRange(selection, scroll: false)   // clamped to the new length
        accept(disk, modified: modified)
        controller.mergeNotice = MergeNotice(conflicts: result.conflicts)
    }

    /// The buffer now builds on this disk version. NSDocument compares the file's modification date with its own
    /// before each save and shows "changed by another application" when they differ; tell it that we have this version.
    private func accept(_ disk: String, modified: Date?) {
        lastKnownDisk = disk
        if let modified { document?.fileModificationDate = modified }
    }

    private var document: NSDocument? {
        controller?.textView?.window?.windowController?.document as? NSDocument
    }

    private func ask(_ disk: String, modified: Date?) {
        guard !isAsking, let window = controller?.textView?.window else { return }
        isAsking = true
        let alert = NSAlert()
        alert.messageText = "This file was changed by another program."
        alert.informativeText = "You have unsaved edits. Merge combines them with the new version. Reload discards them."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Keep My Edits").keyEquivalent = "\u{1b}"   // Escape changes nothing
        alert.addButton(withTitle: "Reload")
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAsking = false
                switch response {
                case .alertFirstButtonReturn: self.merge(disk, modified: modified)
                case .alertThirdButtonReturn: self.reload(disk, modified: modified)
                default: self.lastKnownDisk = disk   // ask again only for the next outside change
                }
            }
        }
    }
}
