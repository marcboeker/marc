import Foundation
import Testing
@testable import Marcdown

struct PrintTests {
    private func html(_ s: String) -> String { MarkdownHTML.render(s) }

    @Test func escapesCodeAndText() {
        #expect(html("```\n<div>&</div>\n```\n") == "<pre><code>&lt;div&gt;&amp;&lt;/div&gt;\n</code></pre>\n")
        #expect(html("a < b & `<i>`\n") == "<p>a &lt; b &amp; <code>&lt;i&gt;</code></p>\n")
    }

    @Test func headingKeepsInlineMarkup() {
        #expect(html("# A *b*\n") == "<h1>A <em>b</em></h1>\n")
    }

    @Test func gfmExtensions() {
        #expect(html("~~x~~ ~y~\n") == "<p><del>x</del> ~y~</p>\n")
        #expect(html("- [ ] a\n- [x] b\n")
            == "<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> a</li>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> b</li>\n</ul>\n")
        #expect(html("| a |\n|---|\n| b |\n").contains("<td>b</td>"))
        #expect(html("see https://swift.org\n") == "<p>see <a href=\"https://swift.org\">https://swift.org</a></p>\n")
    }

    @Test func keepsRawHTMLAndRelativeImages() {
        #expect(html("<kbd>K</kbd>\n") == "<p><kbd>K</kbd></p>\n")
        #expect(html("![cat](<img/a cat.png>)\n") == "<p><img src=\"img/a%20cat.png\" alt=\"cat\" /></p>\n")
    }

    @Test func pageDropsFrontMatterAndSetsBase() {
        let page = PrintRenderer.page(
            markdown: "---\ntitle: x\n---\n\n# T\n",
            title: "A <b> \"doc\"",
            baseFolder: URL(filePath: "/Users/me/My Notes/", directoryHint: .isDirectory),
            fontFamily: "Iowan Old Style"
        )
        #expect(!page.contains("title: x"))
        #expect(page.contains("<h1>T</h1>"))
        #expect(page.contains("<base href=\"file:///Users/me/My%20Notes/\">"))
        #expect(page.contains("<title>A &lt;b&gt; &quot;doc&quot;</title>"))
        #expect(page.contains("font-family: \"Iowan Old Style\", -apple-system"))
    }

    @Test func pageWithoutFolderHasNoBase() {
        let page = PrintRenderer.page(markdown: "x", title: "t", baseFolder: nil, fontFamily: nil)
        #expect(!page.contains("<base"))
        #expect(page.contains("font-family: -apple-system"))
    }
}
