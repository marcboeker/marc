import AppKit
import SwiftUI

/// View > Bigger (⌘+), Smaller (⌘−), Default Size. No ⌘0: that is Format > Paragraph.
struct FontSizeCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            let settings = AppearanceSettings.shared
            let range = AppearanceSettings.fontSizeRange
            Section {
                Button("Bigger") { settings.stepFontSize(by: 1) }
                    .keyboardShortcut("+")
                    .disabled(settings.fontSize >= range.upperBound)
                Button("Smaller") { settings.stepFontSize(by: -1) }
                    .keyboardShortcut("-")
                    .disabled(settings.fontSize <= range.lowerBound)
                Button("Default Size") { settings.fontSize = AppearanceSettings.defaultFontSize }
                    .disabled(settings.fontSize == AppearanceSettings.defaultFontSize)
            }
        }
    }

    /// On a U.S. keyboard "+" is ⇧=, and people press ⌘= for Bigger. A menu item has only one
    /// shortcut, so a key monitor takes ⌘= too.
    @MainActor
    static func installEqualsShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                  event.charactersIgnoringModifiers == "="
            else { return event }
            AppearanceSettings.shared.stepFontSize(by: 1)
            return nil
        }
    }
}
