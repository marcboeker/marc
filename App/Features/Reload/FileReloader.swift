import AppKit

/// Reloads a file when another process changes it. One per open file; `MarcFile.presentedItemDidChange` calls it.
/// Shown in the editor: a clean buffer is replaced quietly (undo history cleared, cursor kept); a buffer with
/// unsaved edits asks first: merge, keep the edits, or reload.
/// Not shown: a clean file takes the disk text quietly; a file with unsaved edits gets `needsDiskReview`,
/// and the question comes when it is shown (`EditorController.fileShown`).
@MainActor
final class FileReloader {
    private unowned let file: MarcFile
    private var isAsking = false
    /// The newest disk version while the question shows. The answer applies to it, not to the one first asked about.
    private var pending: Disk?

    init(file: MarcFile) {
        self.file = file
    }

    /// The editor, when it shows this file.
    private var editor: EditorController? {
        guard let editor = OpenFiles.shared.editor, editor.file === file, editor.textView != nil else { return nil }
        return editor
    }

    /// The file's text and modification date now. Nil when it is gone or mid-save: keep the old text, the next change retries.
    nonisolated static func read(_ url: URL) -> Disk? {
        // Date first: if the file changes between the two reads, the date is the older one and NSDocument still warns.
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return Disk(text: text, modified: modified)
    }

    struct Disk: Sendable {
        let text: String
        let modified: Date?
    }

    /// Read the file now and compare.
    func fileChanged() {
        guard let url = file.fileURL else { return }
        guard let read = Self.read(url) else {
            // Gone: there is no disk version to review against, and the buffer is the only copy.
            // Without this the file could never close or autosave again.
            if !FileManager.default.fileExists(atPath: url.path) { file.needsDiskReview = false }
            return
        }
        diskChanged(read)
    }

    func diskChanged(_ read: Disk?) {
        guard let read else { return }
        if isAsking {
            pending = read
            return
        }
        let disk = read.text, modified = read.modified
        let editor = editor
        let buffer = editor?.currentText ?? file.text
        switch ReloadPolicy.action(disk: disk, buffer: buffer, lastKnownDisk: file.lastKnownDisk) {
        case .ignore:
            file.lastKnownDisk = disk
            file.needsDiskReview = false
        case .reload:
            if let editor {
                reload(disk, modified: modified, in: editor)
            } else {
                file.takeDiskText(disk)
                accept(disk, modified: modified)
            }
        case .ask:
            file.needsDiskReview = true
            ask(disk, modified: modified)   // not shown: no window to ask in, the question waits
        }
    }

    private func reload(_ disk: String, modified: Date?, in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let selection = editor.selectedRange
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        guard editor.replace(whole, with: disk) else { return }
        editor.setSelectedRange(selection, scroll: false)   // clamped to the new length
        textView.undoManager?.removeAllActions()
        accept(disk, modified: modified)
        // The engine pushes the text into the file a turn later; clear the edited mark after that.
        DispatchQueue.main.async { [file] in
            DispatchQueue.main.async { file.updateChangeCount(.changeCleared) }
        }
    }

    /// Merge the outside change into the buffer as one undoable edit. The buffer stays unsaved, so the user checks it first.
    private func merge(_ disk: String, modified: Date?, in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let result = Merge.merge(base: file.lastKnownDisk, mine: editor.currentText, theirs: disk)
        let selection = editor.selectedRange
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        guard editor.replace(whole, with: result.text, actionName: "Merge") else { return }
        editor.setSelectedRange(selection, scroll: false)   // clamped to the new length
        accept(disk, modified: modified)
        file.mergeNotice = MergeNotice(conflicts: result.conflicts)
    }

    /// The buffer now builds on this disk version. NSDocument compares the file's modification date with its own
    /// before each save and shows "changed by another application" when they differ; tell it that we have this version.
    private func accept(_ disk: String, modified: Date?) {
        file.lastKnownDisk = disk
        file.needsDiskReview = false
        if let modified { file.fileModificationDate = modified }
    }

    private func ask(_ disk: String, modified: Date?) {
        guard !isAsking, let window = editor?.textView?.window else { return }
        isAsking = true
        pending = Disk(text: disk, modified: modified)
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
                guard let latest = self.pending else { return }
                self.pending = nil
                let disk = latest.text, modified = latest.modified
                // The editor moved to another file meanwhile: ask again when this one is shown.
                guard let editor = self.editor else { return }
                switch response {
                case .alertFirstButtonReturn: self.merge(disk, modified: modified, in: editor)
                case .alertThirdButtonReturn: self.reload(disk, modified: modified, in: editor)
                default: self.accept(disk, modified: modified)   // ask again only for the next outside change
                }
            }
        }
    }
}
