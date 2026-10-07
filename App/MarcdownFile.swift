import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// Declared as imported in Resources/Info.plist.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// One open Markdown file (UTF-8). It has no window controllers: it lives in `OpenFiles`, and the main
/// window shows the selected one. NSDocument still does reading, saving, autosave, recents and the
/// unsaved-changes questions. Info.plist names this class (`NSDocumentClass`) for the Markdown type.
@Observable
final class MarcdownFile: NSDocument, Identifiable {
    let id = UUID()

    /// The editor writes every edit here through `edit(_:)`.
    private(set) var text = "" {
        didSet { analyze() }
    }

    /// `fileURL`, but observable: Save As, Move To and Rename change it.
    private(set) var url: URL? {
        didSet {
            analyze()   // relative links resolve against the new folder
            OpenFiles.shared.pins.fileMoved(from: oldValue, to: url)   // a pin follows a rename or move
        }
    }

    /// The name in the title bar: the file name without extension, or "Untitled".
    /// Not `displayName` minus extension: with a hidden extension, "Notes 1.2" would lose ".2".
    var title: String { url?.deletingPathExtension().lastPathComponent ?? displayName }

    /// The file's text when we last read, wrote, or reloaded it. A buffer equal to this has no unsaved edits.
    @ObservationIgnored var lastKnownDisk = ""

    /// Unsaved edits (`isDocumentEdited`), observable.
    private(set) var isDirty = false

    /// Another program changed the file while it had unsaved edits, and the user has not chosen merge,
    /// keep or reload yet. The question comes when the file is shown; autosave and close wait for it.
    var needsDiskReview = false

    /// The last merge with the file on disk, shown as a short notice. Nil when none shows.
    var mergeNotice: MergeNotice?

    /// Headings, for the sidebar outline. See `analyze()`.
    private(set) var outline: [OutlineItem] = []

    /// Lint results, for the gutter. See `analyze()`.
    private(set) var lintIssues: [LintIssue] = []

    @ObservationIgnored private var analysis: Task<Void, Never>?
    @ObservationIgnored private var isAnalyzed = false

    /// Handles outside changes to the file (see `presentedItemDidChange`).
    @ObservationIgnored private(set) lazy var reloader = FileReloader(file: self)

    /// The text `data(ofType:)` last wrote, until the save finishes.
    @ObservationIgnored private var writtenText: String?

    override class var autosavesInPlace: Bool { true }

    /// No File Format pop-up in the save panel: plain text (Info.plist) is only for opening .txt files.
    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    @ObservationIgnored
    override nonisolated var fileURL: URL? {
        didSet { MainActor.assumeIsolated { self.url = fileURL } }   // NSDocument sets it on the main thread
    }

    /// An edit from the editor. Marks the file as changed, which starts autosave.
    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        updateChangeCount(.changeDone)
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // Main thread: `canConcurrentlyReadDocuments` is false.
        MainActor.assumeIsolated {
            self.text = text
            lastKnownDisk = text
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        writtenText = text
        return Data(text.utf8)
    }

    /// A save to the file itself (not a copy or a draft) makes the written text the disk version.
    override func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        writtenText = nil
        let toFile = [.saveOperation, .saveAsOperation, .autosaveInPlaceOperation].contains(saveOperation)
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            MainActor.assumeIsolated {
                if error == nil, toFile, let written = self.writtenText { self.lastKnownDisk = written }
                self.writtenText = nil
            }
            completionHandler(error)
        }
    }

    /// Unsaved outside changes wait for the user's choice; saving now would overwrite them.
    override func autosave(
        withImplicitCancellability autosavingIsImplicitlyCancellable: Bool,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if needsDiskReview {
            completionHandler(CocoaError(.userCancelled))
        } else {
            super.autosave(withImplicitCancellability: autosavingIsImplicitlyCancellable, completionHandler: completionHandler)
        }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        isDirty = isDocumentEdited
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        isDirty = isDocumentEdited
    }

    /// Another program changed the file. Our reloader handles it for every open file, shown or not;
    /// NSDocument's own handling (it can revert a clean document behind the editor's back) does not run.
    /// The read happens here, on the presenter's serial queue, so the main thread does no file I/O and
    /// changes arrive in order.
    override nonisolated func presentedItemDidChange() {
        guard let url = fileURL else { return }
        let disk = FileReloader.read(url)
        DispatchQueue.main.async { self.reloader.diskChanged(disk) }
    }

    /// Outline and lint, recomputed off the main thread when the text or the folder changes: at once
    /// the first time, else when typing pauses. Hidden files change only on reload, so this costs
    /// little, and a switch shows a file's results at once.
    private func analyze() {
        analysis?.cancel()
        let text = text, folder = url?.deletingLastPathComponent(), wait = isAnalyzed
        analysis = Task { [weak self] in
            if wait { try? await Task.sleep(for: .milliseconds(300)) }   // a newer change cancels this
            guard !Task.isCancelled else { return }
            let (headings, issues) = await Task.detached {
                (Marcdown.outline(of: text), Marcdown.lint(text, documentFolder: folder))
            }.value
            guard !Task.isCancelled, let self else { return }
            isAnalyzed = true
            if headings != outline { outline = headings }
            if issues != lintIssues { lintIssues = issues }
        }
    }

    /// The file changed on disk and has no unsaved edits, and the editor does not show it: take the disk text.
    /// The engine drops the file's undo history when it shows the changed text.
    func takeDiskText(_ disk: String) {
        text = disk
        updateChangeCount(.changeCleared)
    }

    // MARK: No windows of its own

    override func makeWindowControllers() {}

    /// Every way AppKit opens or creates a document (Open, Open Recent, Finder, Dock, New, Duplicate,
    /// web clip) ends here: show it in the main window.
    override func showWindows() {
        OpenFiles.shared.show(self)
    }

    override var windowForSheet: NSWindow? {
        OpenFiles.shared.window ?? super.windowForSheet
    }

    /// Every way a document closes ends here, so the store never keeps a closed file.
    override func close() {
        super.close()
        OpenFiles.shared.remove(self)
    }

    /// Untitled with text: closing asks Save / Don't Save / Cancel.
    var asksBeforeClosing: Bool { fileURL == nil && !text.isEmpty }

    /// Ready to close? A file with a URL autosaves silently (NSDocument's `canClose`). An untitled file
    /// with text asks Save / Don't Save / Cancel; an empty one closes without a question. False = cancelled.
    func canClose() async -> Bool {
        if fileURL != nil {
            return await withDocumentCallback { canClose(withDelegate: $0, shouldClose: $1, contextInfo: $2) }
        }
        guard asksBeforeClosing else { return true }
        switch await askToSave() {
        case .alertFirstButtonReturn:
            return await withDocumentCallback { save(withDelegate: $0, didSave: $1, contextInfo: $2) }
        case .alertSecondButtonReturn:
            discardUntitledText()
            return true
        default:
            return false
        }
    }

    /// Our own question, not NSDocument's: its answer depends on "Ask to keep changes when closing
    /// documents" in System Settings and can keep untitled text as a draft for the next launch.
    private func askToSave() async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to the document “\(displayName as String)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save").keyEquivalent = "d"
        alert.buttons.last?.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard let window = windowForSheet, window.isVisible else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }

    /// Don't Save: no draft stays behind in the autosave folder.
    private func discardUntitledText() {
        if let draft = autosavedContentsFileURL {
            try? FileManager.default.removeItem(at: draft)
            autosavedContentsFileURL = nil
        }
        updateChangeCount(.changeCleared)
    }

    /// Runs an NSDocument method that reports back through a delegate selector `(document, flag, contextInfo)`.
    private func withDocumentCallback(
        _ start: (Any, Selector, UnsafeMutableRawPointer) -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let callback = DocumentCallback { continuation.resume(returning: $0) }
            // The document does not retain its delegate; the callback releases this.
            start(callback, #selector(DocumentCallback.document(_:flag:contextInfo:)),
                  Unmanaged.passRetained(callback).toOpaque())
        }
    }
}

/// Target for NSDocument's selector-based callbacks (`canClose`, `saveDocument`).
@MainActor
private final class DocumentCallback: NSObject {
    let done: (Bool) -> Void

    init(done: @escaping (Bool) -> Void) {
        self.done = done
    }

    @objc func document(_ document: NSDocument, flag: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if let contextInfo { Unmanaged<DocumentCallback>.fromOpaque(contextInfo).release() }
        done(flag)
    }
}

