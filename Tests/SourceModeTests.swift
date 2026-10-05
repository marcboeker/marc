import AppKit
import Testing
import MarkdownEngine
@testable import Marc

/// View > Show Markdown Source: the engine's raw mode with Marc's light highlighting.
@MainActor
struct SourceModeTests {
    private static let text = "# Title\n\nSome **bold** and `code`.\n\n- item\n"

    private func sourceEditor(_ text: String = Self.text) async throws -> (textView: NSTextView, window: NSWindow) {
        var config = MarkdownEditorConfiguration()
        config.theme = .marc
        config.rawSourceMode = true
        return try #require(await makeTestEditor(text: text, configuration: config))
    }

    private func font(_ textView: NSTextView, at location: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    private func color(_ textView: NSTextView, at location: Int) -> NSColor? {
        textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    private func isBold(_ font: NSFont?) -> Bool {
        font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
    }

    @Test func everyCharacterKeepsTheBodySize() async throws {
        let (textView, window) = try await sourceEditor()
        defer { withExtendedLifetime(window) {} }
        #expect(textView.string == Self.text)
        let bodySize = try #require(font(textView, at: (Self.text as NSString).range(of: "Some").location)).pointSize
        for location in 0..<(Self.text as NSString).length {
            #expect(font(textView, at: location)?.pointSize == bodySize)
            #expect(color(textView, at: location)?.alphaComponent != 0)
        }
    }

    @Test func markersAreMutedAndContentIsStyled() async throws {
        let (textView, window) = try await sourceEditor()
        defer { withExtendedLifetime(window) {} }
        let text = Self.text as NSString
        let muted = MarkdownEditorTheme.marc.mutedText
        #expect(color(textView, at: 0) == muted)                                        // #
        #expect(isBold(font(textView, at: text.range(of: "Title").location)))
        #expect(color(textView, at: text.range(of: "**").location) == muted)
        #expect(isBold(font(textView, at: text.range(of: "bold").location)))
        #expect(!isBold(font(textView, at: text.range(of: "Some").location)))
        #expect(color(textView, at: text.range(of: "`").location) == muted)
        #expect(color(textView, at: text.range(of: "code").location) == MarkdownEditorTheme.marc.inlineCodeText)
        #expect(color(textView, at: text.range(of: "- ").location) == muted)
    }

    @Test func typingHighlightsTheNewLine() async throws {
        let (textView, window) = try await sourceEditor()
        defer { withExtendedLifetime(window) {} }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText("## Next", replacementRange: textView.selectedRange())
        let location = (textView.string as NSString).range(of: "## Next").location
        #expect(color(textView, at: location) == MarkdownEditorTheme.marc.mutedText)
        #expect(isBold(font(textView, at: location + 3)))
        #expect(font(textView, at: location + 3)?.pointSize == font(textView, at: 10)?.pointSize)
    }

    @Test func nestedListMarkersAndTaskBoxesAreMuted() async throws {
        let source = "- top\n  1. nested\n    - [x] task\n\n```\n- code\n```\n\n***\n"
        let (textView, window) = try await sourceEditor(source)
        defer { withExtendedLifetime(window) {} }
        let text = source as NSString
        let muted = MarkdownEditorTheme.marc.mutedText
        #expect(color(textView, at: text.range(of: "- top").location) == muted)
        #expect(color(textView, at: text.range(of: "1.").location) == muted)
        #expect(color(textView, at: text.range(of: "- [x]").location) == muted)
        #expect(color(textView, at: text.range(of: "[x]").location + 1) == muted)
        #expect(color(textView, at: text.range(of: "nested").location) != muted)
        #expect(color(textView, at: text.range(of: "task").location) != muted)
        #expect(color(textView, at: text.range(of: "- code").location) != muted)    // code block, no list
        #expect(color(textView, at: text.range(of: "***").location) == muted)
    }

    @Test func tableDelimiterRowAndPipesAreMuted() async throws {
        let source = "| a | b |\n|---|:-:|\n| c | d |\n"
        let (textView, window) = try await sourceEditor(source)
        defer { withExtendedLifetime(window) {} }
        let text = source as NSString
        let muted = MarkdownEditorTheme.marc.mutedText
        let delimiter = text.range(of: "|---|:-:|")
        for location in delimiter.location..<NSMaxRange(delimiter) {
            #expect(color(textView, at: location) == muted)
        }
        #expect(color(textView, at: 0) == muted)
        #expect(color(textView, at: text.range(of: "a").location) != muted)
        #expect(color(textView, at: text.range(of: "d").location) != muted)
    }

    @Test func typingInALaterBlockHighlightsIt() async throws {
        let (textView, window) = try await sourceEditor()
        defer { withExtendedLifetime(window) {} }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText("  - sub **b**", replacementRange: textView.selectedRange())
        let text = textView.string as NSString
        let muted = MarkdownEditorTheme.marc.mutedText
        #expect(color(textView, at: text.range(of: "- sub").location) == muted)
        #expect(isBold(font(textView, at: text.range(of: "**b").location + 2)))
        #expect(isBold(font(textView, at: text.range(of: "bold").location)))       // earlier block kept
    }
}
