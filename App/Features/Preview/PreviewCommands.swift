import SwiftUI

/// View > Preview (⌃⌘P) and Side by Side (⌥⌘P), below Show Sidebar. A check mark shows the active mode.
/// ⌃⌘P and ⌥⌘P are free: Print is ⌘P, the command launcher ⇧⌘P, Page Setup ⌥⇧⌘P, and the engine binds neither.
struct PreviewCommands: Commands {
    @FocusedValue(\.editorController) private var controller

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            item("Preview", .overlay, "p", [.command, .control])
            item("Side by Side", .split, "p", [.command, .option])
        }
    }

    private func item(_ title: String, _ mode: PreviewMode, _ key: KeyEquivalent, _ modifiers: EventModifiers) -> some View {
        Toggle(title, isOn: Binding(
            get: { controller?.previewMode == mode },
            set: { _ in controller?.togglePreview(mode) }
        ))
        .keyboardShortcut(key, modifiers: modifiers)
        .disabled(controller == nil)
    }
}
