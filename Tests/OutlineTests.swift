import Foundation
import Testing
@testable import Marc

struct OutlineTests {
    private func substring(_ text: String, _ item: OutlineItem) -> String {
        (text as NSString).substring(with: item.range)
    }

    @Test func levelsAndTitles() {
        let items = outline(of: "# One\n\ntext\n\n### Three\n## Two ##\n")
        #expect(items.map(\.level) == [1, 3, 2])
        #expect(items.map(\.title) == ["One", "Three", "Two"])
    }

    @Test func setext() {
        let text = "Title\n=====\n\nSub\n---\n"
        let items = outline(of: text)
        #expect(items.map(\.level) == [1, 2])
        #expect(items.map(\.title) == ["Title", "Sub"])
        #expect(items[0].range.location == 0)
        #expect(items[1].range.location == 13)
    }

    @Test func codeBlocksIgnored() {
        let text = "```\n# not\n```\n\n    # indented\n\n# real\n"
        #expect(outline(of: text).map(\.title) == ["real"])
    }

    @Test func frontMatterSkipped() {
        let text = "---\ntitle: x\n# comment\n---\n# Head\n"
        let items = outline(of: text)
        #expect(items.map(\.title) == ["Head"])
        #expect(items[0].range.location == 27)
        #expect(outline(of: "---\na: b\n...\n# H\n").map(\.title) == ["H"])
    }

    @Test func unclosedFrontMatterIsNotFrontMatter() {
        #expect(outline(of: "---\n# H\n").map(\.title) == ["H"])
    }

    @Test func inlineMarkupStripped() {
        let items = outline(of: "# A *b* **c** `d` [e](http://x) ![f](x.png) ~~g~~\n")
        #expect(items.map(\.title) == ["A b c d e f g"])
    }

    @Test func offsetsWithNonASCII() {
        let text = "---\nname: Jörg 😀\n---\nÄpfel 😀 text\n\n## Grüße 😀 Welt\n\n# Ende\n"
        let items = outline(of: text)
        #expect(items.map(\.title) == ["Grüße 😀 Welt", "Ende"])
        #expect(items.map { substring(text, $0) } == ["## Grüße 😀 Welt", "# Ende"])
    }

    @Test func setextOffsetsWithNonASCII() {
        let text = "😀 ü\n\nÜber 😀\n======\n"
        let items = outline(of: text)
        #expect(items.count == 1)
        #expect(substring(text, items[0]) == "Über 😀\n======")
    }

    @Test func empty() {
        #expect(outline(of: "").isEmpty)
        #expect(outline(of: "just text").isEmpty)
    }
}
