import AppKit
import Testing
@testable import MarkdownEngine

/// Markdown elements the editor used to show wrong: tilde fences, indented code, setext
/// headings, code and lists in quotes, links in table cells, image titles, loose-list
/// paragraphs, HTML comments.
struct MarkdownElementTests {
    private func kinds(_ text: String) -> [BlockKind] {
        BlockParser.computeBlocks(text).map(\.kind)
    }

    // MARK: Fences

    @Test func tildeFenceIsCode() {
        #expect(kinds("~~~json\n{}\n~~~\n") == [.fencedCode])
    }

    @Test func fenceClosesOnlyWithSameCharacterAndLength() {
        // A ``` line does not close a ~~~ block, and ```` needs four backticks to close.
        #expect(kinds("~~~\na\n```\nb\n~~~\n") == [.fencedCode])
        #expect(kinds("````\na\n```\nb\n````\n") == [.fencedCode])
        // A fence line with an info string closes nothing.
        let blocks = BlockParser.computeBlocks("```\na\n```js\nb\n```\n")
        #expect(blocks.map(\.kind) == [.fencedCode])
        #expect(blocks[0].range.length == ("```\na\n```js\nb\n```\n" as NSString).length)
    }

    @Test func backtickInfoStringWithBacktickIsNoFence() {
        #expect(BlockParser.fenceOpening("```a`b") == nil)
        #expect(BlockParser.fenceOpening("~~~a`b") != nil)
    }

    @Test func tildeFenceTokenCarriesLanguage() {
        let text = "~~~json\n{}\n~~~\n"
        let token = MarkdownTokenizer.parseTokensViaAST(in: text).first { $0.kind == .codeBlock }
        #expect(token.map { MarkdownTokenizer.extractLanguage(from: $0, in: text) } == "json")
    }

    @Test func fenceCensusCountsTildes() {
        #expect(MarkdownDetection.tripleBacktickCount(in: "~~~\na\n~~~ ``` ~~") == 3)
        let text = "x ~~~~~~ y" as NSString
        #expect(MarkdownDetection.backtickWindowCount(in: text, around: NSRange(location: 4, length: 1)) == 2)
    }

    // MARK: Indented code

    @Test func indentedCodeAfterBlankLine() {
        #expect(kinds("Text:\n\n    a\n\n    b\n\nAfter\n") == [.paragraph, .blank, .indentedCode, .blank, .paragraph])
    }

    @Test func indentedLineContinuesParagraph() {
        #expect(kinds("Text\n    more\n") == [.paragraph])
    }

    @Test func indentedLinesInListAreNoCode() {
        #expect(kinds("- item\n\n    more text\n") == [.list, .blank, .paragraph])
    }

    @Test func indentedCodeRendersAsHTMLCode() {
        let html = MarkdownHTMLRenderer.html(from: "Text:\n\n    let a = 1\n")
        #expect(html.contains("<pre><code>let a = 1</code></pre>"))
    }

    // MARK: Setext headings

    @Test func setextHeadings() {
        let nodes = DocumentAST.parse("Title\n=====\n\nSub\n---\n")
        guard case .heading(let level1, _, let markers1, _) = nodes[0],
              case .heading(let level2, _, _, _) = nodes[2] else {
            Issue.record("no headings: \(nodes)")
            return
        }
        #expect(level1 == 1)
        #expect(level2 == 2)
        #expect(markers1 == [NSRange(location: 6, length: 5)])
    }

    @Test func ruleAfterBlankLineStaysRule() {
        #expect(kinds("Text\n\n---\n") == [.paragraph, .blank, .thematicBreak])
    }

    // MARK: Quotes

    @Test func codeInQuoteIsNoInlineCode() {
        let text = "> Text\n>\n> ```js\n> a `b` c\n> ```\n"
        let nodes = DocumentAST.parse(text)
        guard case .blockquote(_, let inlines) = nodes.first else {
            Issue.record("no quote")
            return
        }
        #expect(!inlines.contains { if case .code = $0 { true } else { false } })
        let runs = DocumentAST.quoteCodeRuns(NSRange(location: 0, length: (text as NSString).length), text as NSString)
        #expect(runs.count == 1)
        #expect(runs.first.map { (text as NSString).substring(with: $0.openFence) } == "```js")
    }

    // MARK: Tables and images

    @Test func linkInTableCellShowsItsText() {
        let cell = MarkdownStyler.formattedCellString("[link](https://example.com)", baseFont: .systemFont(ofSize: 13),
                                                      header: false, theme: .default, latex: NoOpLatexRenderer())
        #expect(cell.string == "link")
        #expect(cell.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func imageSourceDropsTitle() {
        #expect(MarkdownStyler.imageSource(#"pic.png "A title""#) == "pic.png")
        #expect(MarkdownStyler.imageSource("<my pic.png>") == "my pic.png")
        #expect(MarkdownStyler.imageSource(" pic.png ") == "pic.png")
    }

    // MARK: Editor styling

    /// The editor's styled storage for `body`, with the caret on a first line of its own.
    @MainActor
    private func styled(_ body: String) async throws -> (storage: NSTextStorage, text: NSString, window: NSWindow) {
        let text = "Caret\n\n" + body
        let (textView, window) = try #require(await makeTestEditor(text: text))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return (try #require(textView.textStorage), text as NSString, window)
    }

    @MainActor @Test func listInQuoteDrawsBullets() async throws {
        let (storage, text, window) = try await styled("> - one\n> - two\n")
        defer { withExtendedLifetime(window) {} }
        let dash = text.range(of: "- two").location
        #expect(storage.attribute(.bulletMarker, at: dash, effectiveRange: nil) as? Bool == true)
        let style = storage.attribute(.paragraphStyle, at: dash, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.headIndent ?? 0) > (style?.firstLineHeadIndent ?? 0))
    }

    @MainActor @Test func setextUnderlineFoldsAway() async throws {
        let (storage, text, window) = try await styled("Title\n=====\n")
        defer { withExtendedLifetime(window) {} }
        let title = storage.attribute(.font, at: text.range(of: "Title").location, effectiveRange: nil) as? NSFont
        #expect((title?.pointSize ?? 0) > 20)
        let underline = storage.attribute(.paragraphStyle, at: text.range(of: "===").location, effectiveRange: nil) as? NSParagraphStyle
        #expect((underline?.maximumLineHeight ?? 99) < 1)
    }

    @MainActor @Test func looseListParagraphStartsAtItemText() async throws {
        let (storage, text, window) = try await styled("- item\n\n  more text\n")
        defer { withExtendedLifetime(window) {} }
        let item = storage.attribute(.paragraphStyle, at: text.range(of: "item").location, effectiveRange: nil) as? NSParagraphStyle
        let more = storage.attribute(.paragraphStyle, at: text.range(of: "more").location, effectiveRange: nil) as? NSParagraphStyle
        #expect(more?.firstLineHeadIndent == item?.headIndent)
    }

    @MainActor @Test func inlineImageShowsOnlyItsAltText() async throws {
        let (storage, text, window) = try await styled(#"Look: ![icon](pic.png "A title") here"# + "\n")
        defer { withExtendedLifetime(window) {} }
        let url = text.range(of: "pic.png").location
        #expect(storage.attribute(.foregroundColor, at: url, effectiveRange: nil) as? NSColor == .clear)
        let alt = storage.attribute(.foregroundColor, at: text.range(of: "icon").location, effectiveRange: nil) as? NSColor
        #expect(alt != .clear)
    }

    @MainActor @Test func htmlCommentIsDimmedWithoutLigatures() async throws {
        let (storage, text, window) = try await styled("<!-- note -->\n")
        defer { withExtendedLifetime(window) {} }
        let at = text.range(of: "<!--").location
        #expect(storage.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor == MarkdownEditorTheme.default.disabledText)
        #expect(storage.attribute(.ligature, at: at, effectiveRange: nil) as? Int == 0)
    }

    @MainActor @Test func codeInQuoteUsesTheCodeFont() async throws {
        let (storage, text, window) = try await styled("> ```\n> a `b` c\n> ```\n")
        defer { withExtendedLifetime(window) {} }
        let font = storage.attribute(.font, at: text.range(of: "a `b`").location, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
        #expect(storage.attribute(.inlineCodeBackground, at: text.range(of: "`b`").location, effectiveRange: nil) == nil)
    }
}
