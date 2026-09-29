import Testing
import Foundation
@testable import Marc

/// Test input marks the selection with `|` (cursor) or `«…»` (range).
private func make(_ marked: String) -> TextEdit {
    if let open = marked.range(of: "«"), let close = marked.range(of: "»") {
        let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        let start = (String(marked[..<open.lowerBound]) as NSString).length
        let inner = String(marked[open.upperBound..<close.lowerBound]) as NSString
        return TextEdit(text: text, selection: NSRange(location: start, length: inner.length))
    }
    let bar = marked.range(of: "|")!
    let start = (String(marked[..<bar.lowerBound]) as NSString).length
    return TextEdit(text: marked.replacingOccurrences(of: "|", with: ""), selection: NSRange(location: start, length: 0))
}

/// Render an edit back in the same notation.
private func show(_ e: TextEdit) -> String {
    let ns = e.text as NSString
    if e.selection.length == 0 {
        return ns.replacingCharacters(in: e.selection, with: "|")
    }
    let end = NSMaxRange(e.selection)
    return ns.substring(to: e.selection.location) + "«" + ns.substring(with: e.selection) + "»" + ns.substring(from: end)
}

private func line(_ t: MarkdownEdits.LineTarget, _ s: String) -> String { show(MarkdownEdits.line(t, make(s))) }
private func inline(_ m: String, _ s: String) -> String { show(MarkdownEdits.inline(m, make(s))) }
private func link(_ s: String, url: String? = nil) -> String { show(MarkdownEdits.link(make(s), url: url)) }

struct ShortcutsTests {
    // MARK: Headings and line prefixes

    @Test func headingApplyReplaceRemove() {
        #expect(line(.heading(2), "hel|lo") == "## hel|lo")
        #expect(line(.heading(2), "# hel|lo") == "## hel|lo")
        #expect(line(.heading(2), "## hel|lo") == "hel|lo")
        #expect(line(.heading(6), "hello|") == "###### hello|")
    }

    @Test func headingCursorInsidePrefixMovesToBody() {
        #expect(line(.paragraph, "#| Title") == "|Title")
    }

    @Test func headingOnMultipleLines() {
        #expect(line(.heading(1), "«a\nb\nc»") == "«# a\n# b\n# c»")
        #expect(line(.heading(1), "«# a\n# b\n# c»") == "«a\nb\nc»")
        #expect(line(.heading(1), "«# a\nb»") == "«# a\n# b»")
    }

    @Test func selectionEndingAtLineStartDoesNotTouchNextLine() {
        #expect(line(.quote, "«a\n»b") == "«> a\n»b")
    }

    @Test func paragraphStripsAnyPrefix() {
        #expect(line(.paragraph, "«## a\n> b\n- c\n- [x] d\n12. e\nplain»") == "«a\nb\nc\nd\ne\nplain»")
    }

    @Test func quoteToggle() {
        #expect(line(.quote, "a|") == "> a|")
        #expect(line(.quote, "> a|") == "a|")
        #expect(line(.quote, "«a\n\nb»") == "«> a\n\n> b»")
        #expect(line(.quote, "# a|") == "> a|")
    }

    @Test func bulletAndNumberedSwitching() {
        #expect(line(.bullet, "a|") == "- a|")
        #expect(line(.bullet, "- a|") == "a|")
        #expect(line(.numbered, "- a|") == "1. a|")
        #expect(line(.bullet, "3. a|") == "- a|")
        #expect(line(.numbered, "«a\nb\nc»") == "«1. a\n2. b\n3. c»")
        #expect(line(.numbered, "«1. a\n2. b»") == "«a\nb»")
        #expect(line(.numbered, "«a\n\nb»") == "«1. a\n\n2. b»")
    }

    @Test func renumbersMixedSelection() {
        #expect(line(.numbered, "«1. a\nb\n7. c»") == "«1. a\n2. b\n3. c»")
    }

    @Test func taskToggleAndConversion() {
        #expect(line(.task, "a|") == "- [ ] a|")
        #expect(line(.task, "- [ ] a|") == "a|")
        #expect(line(.task, "- [x] a|") == "a|")
        #expect(line(.task, "- a|") == "- [ ] a|")
        #expect(line(.task, "1. a|") == "- [ ] a|")
        #expect(line(.bullet, "- [ ] a|") == "- a|")
        #expect(line(.task, "«- a\n- [x] b»") == "«- [ ] a\n- [x] b»")
    }

    @Test func indentedListsKeepIndent() {
        #expect(line(.numbered, "  - a|") == "  1. a|")
        #expect(line(.task, "    - a|") == "    - [ ] a|")
    }

    @Test func emptyLinesGetPrefix() {
        #expect(line(.bullet, "|") == "- |")
        #expect(line(.heading(3), "a\n|") == "a\n### |")
    }

    @Test func lineToggleRoundTrip() {
        let original = "«one\ntwo\nthree»"
        for target: MarkdownEdits.LineTarget in [.heading(3), .quote, .bullet, .numbered, .task] {
            let once = MarkdownEdits.line(target, make(original))
            #expect(show(MarkdownEdits.line(target, once)) == original)
        }
    }

    @Test func crlfLinesKeepTerminators() {
        let out = MarkdownEdits.line(.bullet, make("«a\r\nb»"))
        #expect(out.text == "- a\r\n- b")
    }

    @Test func emojiInLines() {
        #expect(line(.heading(1), "😀 a|") == "# 😀 a|")
        #expect(line(.quote, "😀|😀") == "> 😀|😀")
    }

    // MARK: Inline

    @Test func boldSelection() {
        #expect(inline("**", "say «hi» now") == "say **«hi»** now")
        #expect(inline("**", "say **«hi»** now") == "say «hi» now")
        #expect(inline("**", "say «**hi**» now") == "say «hi» now")
    }

    @Test func wordAtCursor() {
        #expect(inline("**", "say h|i now") == "say **h|i** now")
        #expect(inline("**", "say **h|i** now") == "say h|i now")
        #expect(inline("*", "say hi| now") == "say *hi|* now")
        #expect(inline("~~", "a wo|rd b") == "a ~~wo|rd~~ b")
        #expect(inline("`", "a wo|rd b") == "a `wo|rd` b")
        #expect(inline("`", "a `wo|rd` b") == "a wo|rd b")
    }

    @Test func emptyNoWordInsertsPair() {
        #expect(inline("**", "a |") == "a **|**")
        #expect(inline("*", "|") == "*|*")
        #expect(inline("~~", "a | b") == "a ~~|~~ b")
    }

    @Test func boldItalicDoNotConfuse() {
        #expect(inline("*", "**«hi»**") == "***«hi»***")
        #expect(inline("**", "*«hi»*") == "***«hi»***")
        #expect(inline("*", "***«hi»***") == "**«hi»**")
        #expect(inline("**", "***«hi»***") == "*«hi»*")
        #expect(inline("*", "**hi|**") == "***hi|***")
        #expect(inline("**", "*hi|*") == "***hi|***")
        #expect(inline("*", "***hi|***") == "**hi|**")
    }

    @Test func boldItalicFullRoundTrip() {
        let start = "«hi»"
        let bold = MarkdownEdits.inline("**", make(start))
        let both = MarkdownEdits.inline("*", bold)
        #expect(both.text == "***hi***")
        let noBold = MarkdownEdits.inline("**", both)
        #expect(noBold.text == "*hi*")
        #expect(show(MarkdownEdits.inline("*", noBold)) == start)
    }

    @Test func whitespaceIsTrimmedFromSelection() {
        #expect(inline("**", "a« hi »b") == "a **«hi»** b")
    }

    @Test func multiWordSelection() {
        #expect(inline("**", "«one two»") == "**«one two»**")
        #expect(inline("~~", "~~«one two»~~") == "«one two»")
    }

    @Test func emojiAndUnicodeRanges() {
        #expect(inline("**", "😀 «héllo» 😀") == "😀 **«héllo»** 😀")
        #expect(inline("**", "😀 **«héllo»** 😀") == "😀 «héllo» 😀")
        #expect(inline("**", "😀 hé|llo 😀") == "😀 **hé|llo** 😀")
        #expect(inline("**", "😀|") == "😀**|**")
        #expect(inline("*", "«😀»") == "*«😀»*")
    }

    @Test func allMarkersSelectedDoesNotCrash() {
        #expect(inline("**", "«****»") == "**«****»**")
    }

    // MARK: Link

    @Test func linkPlaceholder() {
        #expect(link("«site»") == "[site](«url»)")
        #expect(link("a si|te b") == "a [site](«url») b")
    }

    @Test func linkWithPasteboardURL() {
        #expect(link("«site»", url: "https://x.y") == "[site](https://x.y)|")
    }

    @Test func linkWithoutWord() {
        #expect(link("a |") == "a [|](url)")
        #expect(link("a |", url: "https://x.y") == "a [|](https://x.y)")
    }

    @Test func linkUnwrap() {
        #expect(link("[«site»](https://x.y)") == "«site»")
        #expect(link("a [si|te](https://x.y) b") == "a si|te b")
        #expect(link("a [site](htt|ps://x.y) b") == "a site| b")
        #expect(link("«[site](https://x.y)»") == "«site»")
    }

    @Test func imagesAreNotUnwrapped() {
        #expect(link("![a|lt](x.png)") == "![[alt](«url»)](x.png)")
    }

    @Test func linkWithEmoji() {
        #expect(link("😀 «hi»") == "😀 [hi](«url»)")
    }

    // MARK: Code block

    @Test func codeBlockWrapAndUnwrap() {
        #expect(show(MarkdownEdits.codeBlock(make("a\nb|\nc"))) == "a\n```\nb|\n```\nc")
        #expect(show(MarkdownEdits.codeBlock(make("«a\nb»\nc"))) == "```\n«a\nb»\n```\nc")
        #expect(show(MarkdownEdits.codeBlock(make("a\n```\nb|\n```\nc"))) == "a\nb|\nc")
        #expect(show(MarkdownEdits.codeBlock(make("```swift\nlet x|\n```\n"))) == "let x|\n")
    }

    @Test func codeBlockLastLineWithoutNewline() {
        #expect(show(MarkdownEdits.codeBlock(make("a|"))) == "```\na|\n```")
        #expect(show(MarkdownEdits.codeBlock(make("```\na|\n```"))) == "a|\n")
    }

    @Test func codeBlockOnEmptyLine() {
        #expect(show(MarkdownEdits.codeBlock(make("|"))) == "```\n|\n```")
    }

    @Test func codeBlockRoundTrip() {
        let original = "x\n«a\nb»\ny"
        let once = MarkdownEdits.codeBlock(make(original))
        #expect(show(MarkdownEdits.codeBlock(once)) == original)
    }

    @Test func codeBlockUnclosedFenceIsRemoved() {
        #expect(show(MarkdownEdits.codeBlock(make("a\n```\nb|\nc"))) == "a\nb|\nc")
        #expect(show(MarkdownEdits.codeBlock(make("```\nb\n|"))) == "b\n|")
    }

    @Test func codeBlockIgnoresOtherBlocks() {
        #expect(show(MarkdownEdits.codeBlock(make("```\na\n```\nb|"))) == "```\na\n```\n```\nb|\n```")
    }

    // MARK: Rule

    @Test func ruleAfterLine() {
        #expect(show(MarkdownEdits.rule(make("a|"))) == "a\n\n---\n|")
        #expect(show(MarkdownEdits.rule(make("a|\nb"))) == "a\n\n---\n|\nb")
        #expect(show(MarkdownEdits.rule(make("a|\n\nb"))) == "a\n\n---\n|\nb")
    }

    @Test func ruleOnBlankLine() {
        #expect(show(MarkdownEdits.rule(make("a\n|\nb"))) == "a\n\n---\n|\nb")
        #expect(show(MarkdownEdits.rule(make("|"))) == "---\n|")
        #expect(MarkdownEdits.rule(make("a\n\n|\n\nb")).text == "a\n\n---\n\nb")
    }

    // MARK: Minimal replacement

    @Test func minimalReplacement() throws {
        let r = try #require(MarkdownEdits.replacement(from: "abcdef", to: "abXYef"))
        #expect(r.range == NSRange(location: 2, length: 2))
        #expect(r.text == "XY")
        #expect(MarkdownEdits.replacement(from: "same", to: "same") == nil)
        let insert = try #require(MarkdownEdits.replacement(from: "ab", to: "aXb"))
        #expect(insert.range == NSRange(location: 1, length: 0))
        #expect(insert.text == "X")
    }

    @Test func minimalReplacementKeepsSurrogatePairsWhole() throws {
        // 😀 = D83D DE00, 😁 = D83D DE01: shared lead surrogate must not be split.
        let r = try #require(MarkdownEdits.replacement(from: "a😀b", to: "a😁b"))
        #expect(r.range == NSRange(location: 1, length: 2))
        #expect(r.text == "😁")
    }

    @Test func replacementReproducesNewText() {
        let cases = [("", "x"), ("x", ""), ("a\nb", "- a\n- b"), ("aaa", "aa"), ("😀😀", "😀"), ("😀", "😀😀")]
        for (old, new) in cases {
            guard let r = MarkdownEdits.replacement(from: old, to: new) else { continue }
            #expect((old as NSString).replacingCharacters(in: r.range, with: r.text) == new)
        }
    }
}
