import Foundation
import Testing
@testable import Marcdown

struct WebClipMarkdownTests {
    private func name(_ markdown: String, _ url: String = "https://example.com/blog/post.html") -> String {
        WebClipMarkdown.fileName(markdown: markdown, url: URL(string: url)!)
    }

    @Test func firstH1() { #expect(name("Intro\n\n# Hello, World!\n\n# Second") == "hello-world") }
    @Test func linkInHeading() { #expect(name("# [Swift 6](https://swift.org) is out") == "swift-6-is-out") }
    @Test func h2IsNotATitle() { #expect(name("## Sub\n\ntext") == "post") }
    @Test func hostWhenNoPath() { #expect(name("text", "https://example.com/") == "example-com") }
    @Test func firstNonEmptyH1() { #expect(name("# [](/)\n\n# Real Title") == "real-title") }
    @Test func dotsInPathKept() { #expect(name("text", "https://x.org/blog/swift-6.4-released/") == "swift-6-4-released") }
    @Test func webExtensionDropped() { #expect(name("text", "https://x.org/a/page.PHP") == "page") }
    @Test func unicodeKept() { #expect(name("# Über Straße") == "über-straße") }

    @Test func slugCutsAtWordBoundary() {
        let words = Array(repeating: "abcdefghi", count: 10).joined(separator: " ")
        let slug = WebClipMarkdown.slug(words)
        #expect(slug == Array(repeating: "abcdefghi", count: 6).joined(separator: "-"))
    }

    @Test func slugCutsOneLongWord() {
        #expect(WebClipMarkdown.slug(String(repeating: "x", count: 100)) == String(repeating: "x", count: 60))
    }

    @Test func linksBecomeAbsolute() {
        let base = URL(string: "https://example.com/blog/post/")!
        let markdown = "[Home](/) [Next](../next/) [Top](#top) [Ext](https://a.org/x) ![Logo](img/logo.png)"
        #expect(WebClipMarkdown.finish(markdown, base: base) ==
            "[Home](https://example.com/) [Next](https://example.com/blog/next/) "
            + "[Top](https://example.com/blog/post/#top) [Ext](https://a.org/x) "
            + "![Logo](https://example.com/blog/post/img/logo.png)\n")
    }

    @Test func finishKeepsFormattingRules() {
        let base = URL(string: "https://example.com/")!
        #expect(WebClipMarkdown.finish("* a\n* ~~b~~ _c_\n\n***", base: base) == "- a\n- ~~b~~ *c*\n\n---\n")
    }

    @Test func punctuationIsNotSmartened() {
        let text = "Run it with --verbose and \"quotes\" and 'single' ...\n"
        #expect(WebClipMarkdown.finish(text, base: URL(string: "https://example.com/")!) == text)
    }

    @Test func emptyLinksAndHeadingsRemoved() {
        let base = URL(string: "https://example.com/")!
        let markdown = "# [](/)\n\n# Title\n\n## Part[](#part)\n\nText [](/x) end."
        #expect(WebClipMarkdown.finish(markdown, base: base) == "# Title\n\n## Part\n\nText  end.\n")
    }
}
