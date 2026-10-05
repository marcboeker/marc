import SwiftUI

/// View > Preview (⌃⌘P) and Side by Side (⌘\), below Show Sidebar. A check mark shows the active mode.
/// ⌃⌘P is free: Print is ⌘P, Page Setup ⇧⌘P, and the engine binds no ⌃⌘ keys.
struct PreviewCommands: Commands {
    @FocusedValue(\.editorController) private var controller

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            item("Preview", .overlay, "p", [.command, .control])
            item("Side by Side", .split, "\\", .command)
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
