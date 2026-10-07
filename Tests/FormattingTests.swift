import Testing
@testable import Marcdown

struct FormattingTests {
    private func f(_ s: String) -> String { MarkdownFormatting.format(s) }

    @Test func listMarkers() {
        #expect(f("* a\n* b\n") == "- a\n- b\n")
        #expect(f("+ a\n+ b\n") == "- a\n- b\n")
        #expect(f("3. a\n3. b\n3. c\n") == "1. a\n2. b\n3. c\n")
    }

    @Test func headingsAndEmphasis() {
        #expect(f("Title\n=====\n") == "# Title\n")
        #expect(f("_a_ and __b__\n") == "*a* and **b**\n")
    }

    @Test func fencesAndBreaks() {
        #expect(f("    code\n") == "```\ncode\n```\n")
        #expect(f("***\n") == "---\n")
        #expect(f("~~~swift\nx\n~~~\n") == "```swift\nx\n```\n")
    }

    @Test func autolinkCondensed() {
        #expect(f("[https://swift.org](https://swift.org)\n") == "<https://swift.org>\n")
    }

    @Test func trailingNewline() {
        #expect(f("a") == "a\n")
        #expect(f("a\n\n\n") == "a\n")
        #expect(f("") == "")
    }

    @Test func frontMatterSplit() {
        let s = FrontMatterSplit.split("---\ntitle: x\n---\n\n# T\n")
        #expect(s.front == "---\ntitle: x\n---\n\n")
        #expect(s.body == "# T\n")
        #expect(FrontMatterSplit.split("---\na: 1\n...\nbody").front == "---\na: 1\n...\n")
        #expect(FrontMatterSplit.split("---\nno close\n").front == "")
        #expect(FrontMatterSplit.split("text\n---\na\n---\n").front == "")
    }

    @Test func frontMatterVerbatim() {
        let front = "---\ntitle:   \"x\"\nlist:\n    - *a\n---\n"
        #expect(f(front + "* item\n") == front + "- item\n")
        #expect(f(front) == front)
    }

    @Test func idempotent() {
        let samples = [
            "* a\n  * b\n\n1. x\n1. y\n",
            "Title\n---\n\n| a | b |\n|---|---|\n| 1 | 2 |\n",
            "---\nk: v\n---\n\n_x_ __y__ ~~z~~\n",
            "- [ ] todo\n- [x] done\n",
            "line one  \nline two\\\nline three\n",
            "<div>\n  html\n</div>\n\ntext\n",
        ]
        for s in samples { #expect(f(f(s)) == f(s)) }
    }

    @Test func roundTripKeepsContent() {
        let table = f("| a | b |\n|---|---|\n| one | two |\n")
        #expect(table.contains("one") && table.contains("two") && table.contains("|"))
        let tasks = f("- [ ] todo\n- [x] done\n")
        #expect(tasks == "- [ ] todo\n- [x] done\n")
        #expect(f("~~gone~~\n") == "~~gone~~\n")
        #expect(f("<div>\n  html\n</div>\n") == "<div>\n  html\n</div>\n")
        let breaks = f("one  \ntwo\\\nthree\n")
        #expect(breaks.contains("one") && breaks.contains("two") && breaks.contains("three"))
        #expect(breaks.components(separatedBy: "\n").count >= 4)
    }

    @Test func cursorMapping() {
        let old = "* a\n* bcd\n"
        let new = "- a\n- bcd\n"
        // line 1, column 4 -> same in new
        #expect(MarkdownFormatting.mapLocation(8, from: old, to: new) == 8)
        // column clamped to shorter line
        #expect(MarkdownFormatting.mapLocation(9, from: "x\nlonger line\n", to: "x\nab\n") == 4)
        // beyond last line
        #expect(MarkdownFormatting.mapLocation(5, from: "a\nb\nc", to: "a\n") == 2)
        #expect(MarkdownFormatting.mapLocation(0, from: "", to: "x\n") == 0)
    }

    @Test func noChangeWhenFormatted() {
        let s = "# T\n\n- a\n- b\n"
        #expect(f(s) == s)
    }

    @Test func thematicBreakIsThreeDashes() {
        #expect(f("a\n\n***\n\nb\n") == "a\n\n---\n\nb\n")
        // Paragraph directly above: must not become a setext heading.
        #expect(f("a\n***\nb\n") == "a\n\n---\n\nb\n")
        #expect(f("> q\n>\n> ___\n").hasSuffix("> ---\n"))
        #expect(f("- a\n\n  ***\n").hasSuffix("  ---\n"))
    }

    @Test func dashesElsewhereUntouched() {
        let code = "```\n-----\n```\n"
        #expect(f(code) == code)
        #expect(f("    -----\n") == code)
        #expect(f("<div>\n-----\n</div>\n") == "<div>\n-----\n</div>\n")
        let front = "---\na: -----\n---\n"
        #expect(f(front + "\n***\n") == front + "\n---\n")
        #expect(f(f("a\n***\nb\n")) == f("a\n***\nb\n"))
    }
}

@Test func punctuationIsNotSmartened() {
    let text = "Say \"hi\" -- and 'bye' --- ok...\n"
    #expect(MarkdownFormatting.format(text) == text)
}

@Test func frontMatterWithCRLFIsKept() {
    let text = "---\r\ntitle: \"A\"\r\n---\r\n\r\n# Head\r\n"
    let parts = FrontMatterSplit.split(text)
    #expect(parts.front == "---\r\ntitle: \"A\"\r\n---\r\n\r\n")
    #expect(MarkdownFormatting.format(text).hasPrefix(parts.front))
}

@Test func tableCellDashesAreKept() {
    #expect(MarkdownFormatting.format("| a | b |\n|---|---|\n| ----- | x |\n").contains("-----"))
}

@Test func escapesKeepTheirMeaning() {
    // swift-markdown drops backslash escapes; formatting must not turn them into markup.
    for text in ["\\*not emphasis\\*\n", "\\# not a heading\n", "1\\. not a list\n", "a \\<b\\> c\n"] {
        #expect(MarkdownFormatting.format(text) == text)
    }
}

@Test func singleTildeStaysSingle() {
    #expect(MarkdownFormatting.format("H~2~O and ~~gone~~\n") == "H~2~O and ~~gone~~\n")
    #expect(MarkdownFormatting.format("~x~\n", doublingSingleTildes: true) == "~~x~~\n")
}
