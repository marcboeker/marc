import AppKit
import SwiftUI

/// Edit > Find: drives the text view's find bar. SwiftUI's `TextEditingCommands` would add
/// the same menu, but its "Use Selection for Find" takes ⌘E, which is Format > Code here.
struct FindCommands: Commands {
    @FocusedValue(\.editorController) private var controller

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                item("Find…", .showFindInterface, "f")
                item("Find and Replace…", .showReplaceInterface, "f", [.command, .option])
                item("Find Next", .nextMatch, "g")
                item("Find Previous", .previousMatch, "g", [.command, .shift])
                item("Use Selection for Find", .setSearchString)
            }
        }
    }

    private func item(_ title: String, _ action: NSTextFinder.Action,
                      _ key: KeyEquivalent? = nil, _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { controller?.performFind(action) }
            .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: modifiers) })
            .disabled(controller == nil)
    }
}

extension EditorController {
    /// Run a find bar action on this window's text view, even when the outline has focus.
    func performFind(_ action: NSTextFinder.Action) {
        guard let textView else { return }
        // NSTextView reads the action from the sender's tag.
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        textView.performTextFinderAction(sender)
    }
}
