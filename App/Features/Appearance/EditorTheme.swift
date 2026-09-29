import AppKit
import MarkdownEngine

extension MarkdownEditorTheme {
    /// Marc's look: flat code slabs, orange inline-code pills, quote panels, striped table cards.
    static let marc = MarkdownEditorTheme(
        inlineCodeBackground: .appearance(dark: NSColor(srgbRed: 1, green: 0.416, blue: 0.102, alpha: 0.10),
                                          light: NSColor(srgbRed: 1, green: 0.416, blue: 0.102, alpha: 0.09)),
        inlineCodeText: .appearance(dark: NSColor(srgbRed: 1, green: 0.604, blue: 0.361, alpha: 1),
                                    light: NSColor(srgbRed: 0.769, green: 0.278, blue: 0.039, alpha: 1)),
        blockquoteBar: .appearance(dark: NSColor(white: 0.353, alpha: 1),
                                   light: NSColor(srgbRed: 0.69, green: 0.69, blue: 0.71, alpha: 1)),
        blockquoteBackground: .overlay(dark: 0.055, light: 0.035),
        blockquoteText: .labelColor
    )
}

private extension NSColor {
    static func appearance(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}
