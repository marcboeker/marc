import AppKit
import SwiftUI

/// File menu (New, Open…, Open Recent, Close, Save, Pin File, …) and Window > Previous/Next File and the pinned files.
/// Replaces the DocumentGroup items: there are no document windows, so the menu acts on the
/// selected file in `OpenFiles`.
struct FileCommands: Commands {
    @FocusedValue(\.editorController) private var controller
    @Environment(\.openWindow) private var openWindow
    private var files = OpenFiles.shared

    var body: some Commands {
        // Commands live as long as the app, so this is where AppKit-side code gets `openWindow`.
        let _ = files.openMainWindow = { [openWindow] in openWindow(id: "main") }
        CommandGroup(replacing: .newItem) {
            Button("New") { files.newUntitled() }
                .keyboardShortcut("n")
            Button("Open…") { NSDocumentController.shared.openDocument(nil) }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(files.recentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) { files.open(url) }
                }
                Divider()
                Button("Clear Menu") { NSDocumentController.shared.clearRecentDocuments(nil) }
                    .disabled(files.recentURLs.isEmpty)
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { files.closeSelected() }
                .keyboardShortcut("w")
            // Through the editor: an explicit save formats first (see EditorController.saveRequested).
            Button("Save") { _ = controller?.saveRequested() }
                .keyboardShortcut("s")
                .disabled(controller == nil || files.selected == nil)
            Button("Duplicate") { files.selected?.duplicate(nil) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(files.selected == nil)
            // No Rename… (NSDocument renames in a document window's title bar) and no Revert To
            // (it opens the Versions browser, untested without a document window).
            Button("Move To…") { files.selected?.move(nil) }
                .disabled(files.selected == nil)
            // An untitled file has no place to point to, so it cannot be pinned.
            Button(files.pins.isPinned(files.selected?.url) ? "Unpin File" : "Pin File") {
                if let file = files.selected { files.togglePin(file) }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(files.selected?.url == nil)
        }
        CommandGroup(before: .windowArrangement) {
            Button("Previous File") { files.selectNeighbor(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(files.files.count < 2)
            Button("Next File") { files.selectNeighbor(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(files.files.count < 2)
            Divider()
            // One item per pin, ⌥⌘1 to ⌥⌘9; a closed pin opens.
            ForEach(Array(files.pins.items.prefix(9).enumerated()), id: \.element.id) { index, pin in
                Button(pin.name) { files.activate(pin) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
            }
            if !files.pins.items.isEmpty { Divider() }
        }
    }
}
