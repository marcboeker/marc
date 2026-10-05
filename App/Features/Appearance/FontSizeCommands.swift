import AppKit
import SwiftUI

/// View > Show Markdown Source (⌥⌘U, as View Source in Safari), Bigger (⌘+), Smaller (⌘−), Default Size.
/// No ⌘0: that is Format > Paragraph.
struct FontSizeCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            @Bindable var settings = AppearanceSettings.shared
            let range = AppearanceSettings.fontSizeRange
            Section {
                Toggle("Show Markdown Source", isOn: $settings.showsMarkdownSource)
                    .keyboardShortcut("u", modifiers: [.command, .option])
            }
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
