import AppKit
import SwiftUI

/// The files open in the main window, in open order, and which one it shows.
/// Files come in through NSDocumentController (see `MarcFile.showWindows`) and leave through
/// `MarcFile.close`, so AppKit's document list and this one stay the same.
@MainActor
@Observable
final class OpenFiles {
    static let shared = OpenFiles()

    private(set) var files: [MarcFile] = []
    var selectedID: MarcFile.ID?
    /// For File > Open Recent. Updated by MarcDocumentController.
    var recentURLs: [URL] = []

    /// The main window, set by `MainWindowAccessor`. Close and save questions attach their sheets here.
    @ObservationIgnored weak var window: NSWindow?
    /// SwiftUI's `openWindow(id: "main")`, set by FileCommands. Creates the window when there is none
    /// (a launch from Finder or `open -a` does not open the `Window` scene).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    /// The main window's editor, set by ContentView. It shows the selected file.
    @ObservationIgnored weak var editor: EditorController?

    var selected: MarcFile? { files.first { $0.id == selectedID } }

    /// Add the file at the bottom if it is new, select it, and bring the window to the front.
    func show(_ file: MarcFile) {
        if !files.contains(file) { files.append(file) }
        selectedID = file.id
        showWindow()
    }

    /// Bring the main window back, also after it was closed (closing only hides it).
    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    /// Open a file, or select it if it is open already.
    func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    func newUntitled() {
        do {
            try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Called by `MarcFile.close`. A closed selected file passes the selection to the file below it,
    /// else to the one above.
    func remove(_ file: MarcFile) {
        guard let index = files.firstIndex(of: file) else { return }
        files.remove(at: index)
        guard selectedID == file.id else { return }
        selectedID = files.indices.contains(index) ? files[index].id : files.last?.id
    }

    /// Select the file `offset` rows away from the selected one, wrapping around.
    func selectNeighbor(_ offset: Int) {
        guard let index = files.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = files.first?.id
            return
        }
        let count = files.count
        selectedID = files[((index + offset) % count + count) % count].id
    }

    /// Ask (if needed) and close. False when the user cancelled.
    @discardableResult
    func close(_ file: MarcFile) async -> Bool {
        // An outside change waits for merge / keep / reload, which shows when the file is shown.
        // Closing now would save over it; the user closes again after answering.
        if file.needsDiskReview {
            selectedID = file.id
            return false
        }
        // The question is about this file's text: show it.
        if file.asksBeforeClosing { selectedID = file.id }
        guard await file.canClose() else { return false }
        file.close()
        return true
    }

    /// Close every file, for window close and quit. Files that wait for a disk review or ask go
    /// first, so a Cancel leaves all files open.
    func closeAll() async -> Bool {
        let asks = { (file: MarcFile) in file.needsDiskReview || file.asksBeforeClosing }
        for file in files.filter(asks) + files.filter({ !asks($0) }) {
            guard await close(file) else { return false }
        }
        return true
    }

    /// ⌘W: close the selected file; with no file, close the window.
    func closeSelected() {
        if let selected {
            Task { await close(selected) }
        } else {
            window?.performClose(nil)
        }
    }
}

/// Routes AppKit's document machinery (Open…, Open Recent, Finder, Dock, `open -a`) into `OpenFiles`.
/// Created in Main.swift before the app starts, so it is `NSDocumentController.shared`.
final class MarcDocumentController: NSDocumentController {
    override init() {
        super.init()
        // After launch: resolving the recent files' bookmarks touches the disk (slow for network volumes).
        DispatchQueue.main.async { OpenFiles.shared.recentURLs = self.recentDocumentURLs }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        super.noteNewRecentDocumentURL(url)
        // The same update AppKit makes, without resolving every bookmark again.
        let recent = OpenFiles.shared.recentURLs
        OpenFiles.shared.recentURLs = Array(([url] + recent.filter { $0 != url }).prefix(maximumRecentDocumentCount))
    }

    /// Quit: our close flow (file shown, Save / Don't Save / Cancel) instead of AppKit's review panel.
    override func reviewUnsavedDocuments(
        withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
        didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        nonisolated(unsafe) let context = contextInfo
        let delegate = delegate as? NSObject
        Task {
            let reviewed = await OpenFiles.shared.closeAll()
            guard let delegate, let didReviewAllSelector else { return }
            // `- (void)documentController:(NSDocumentController *)c didReviewAll:(BOOL)flag contextInfo:(void *)info`
            typealias Callback = @convention(c) (NSObject, Selector, NSDocumentController, Bool, UnsafeMutableRawPointer?) -> Void
            let callback = unsafeBitCast(delegate.method(for: didReviewAllSelector), to: Callback.self)
            callback(delegate, didReviewAllSelector, self, reviewed, context)
        }
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        OpenFiles.shared.recentURLs = []
    }
}
