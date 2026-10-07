import Foundation
import Testing
import WebKit
@testable import Marc

/// `marcPreview.update` in a real web view: an edit replaces only the blocks that changed.
@MainActor
struct PreviewUpdateTests {
    private let style = DocumentStyle(fontFamily: nil, fontSize: 15, lineSpacing: 2, lineWidth: nil)

    @Test func editReplacesOnlyTheChangedBlock() async throws {
        let page = try await Page(markdown: "# A\n\nfirst\n\n## B\n\nsecond\n\n## B\n", style: style)
        // Headings got ids in the page; they must not count as a change.
        #expect(try await page.headingIDs() == "a b b-1")
        #expect(try await page.update("# A\n\nfirst, edited\n\n## B\n\nsecond\n\n## B\n") == 1)
        #expect(try await page.update("# A\n\nfirst, edited\n\n## B\n\nsecond, edited\n\n## B\n") == 1)
        #expect(try await page.update("# A\n\nfirst, edited\n\n## B\n\nsecond, edited\n\n## B\n") == 0)
        #expect(try await page.headingIDs() == "a b b-1")
        #expect(try await page.matchesFreshPage())
    }

    @Test func keptBlocksTakeNewPositions() async throws {
        let page = try await Page(markdown: "a\n\n- b\n- c\n", style: style)
        #expect(try await page.update("new\n\na\n\n- b\n- c\n") == 1)
        #expect(try await page.positions() == ["1:1-1:3", "3:1-3:1", "5:1-6:3", "5:1-5:3", "6:1-6:3"])
        #expect(try await page.matchesFreshPage())
    }

    @Test func rawHTMLAcrossBlocksStaysOneBlock() async throws {
        let markdown = "a\n\n<details>\n\ninside\n\n</details>\n\nb\n"
        // a, details, inside, /details | b: a raw HTML block joins the block before it.
        #expect(PreviewRenderer.render(markdown: markdown).body.blocks.count == 2)
        let page = try await Page(markdown: markdown, style: style)
        #expect(try await page.update("a\n\n<details>\n\ninside, edited\n\n</details>\n\nb\n") == 1)
        #expect(try await page.matchesFreshPage())
        #expect(try await page.evaluate("return document.querySelector('details p').textContent") as? String == "inside, edited")
        #expect(try await page.update("a, edited\n\n<details>\n\ninside, edited\n\n</details>\n\nb\n") == 1)
        #expect(try await page.matchesFreshPage())
    }

    @Test func unclosedRawHTMLTakesTheRest() async throws {
        let markdown = "a\n\n<div>\n\nb\n\nc\n"
        #expect(PreviewRenderer.render(markdown: markdown).body.blocks.count == 1)
        let page = try await Page(markdown: markdown, style: style)
        #expect(try await page.update("a\n\n<div>\n\nb\n\nc, edited\n") == 1)
        #expect(try await page.matchesFreshPage())
    }

    @Test func pageWithOtherBlocksGetsAllOfThem() async throws {
        let page = try await Page(markdown: "a\n\nb\n", style: style)
        // A change for blocks the page does not have fails; then all blocks go in.
        let other = PreviewRenderer.render(markdown: "x\n\ny\n\nz\n").body
        #expect(try await page.send(other.change(from: other, pageKnowsBlocks: true)) == -1)
        #expect(try await page.send(page.body.full) == 2)
        #expect(try await page.matchesFreshPage())
        #expect(try await page.update("a\n\nb, edited\n") == 1)
        #expect(try await page.matchesFreshPage())
    }

    @Test func editsInManyPlacesMatchAFreshPage() async throws {
        let page = try await Page(markdown: "", style: style)
        for markdown in [
            "# T\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- x\n  - y\n\n    code\n",
            "# T\n\n| a | b |\n|---|---|\n| 1 | 3 |\n\n- x\n  - y\n  - z\n\n    code\n",
            "intro\n\n# T\n\n<span>raw</span> text\n\n- x\n\n- y\n\n---\n",
            "",
            "one\n",
        ] {
            _ = try await page.update(markdown)
            #expect(try await page.matchesFreshPage(), "\(markdown)")
        }
    }

    // MARK: Blocks in Swift

    @Test func blocksJoinToTheSameHTMLAsPrint() {
        let markdown = """
            # T

            | a | b |
            |---|:-:|
            | `1` | ~~2~~ |

            1. x
               - y

                 > q
            2. z

            - [ ] task
            - [x] done

            <div class="note">

            *md* in html

            </div>

            <!-- a comment -->

            ```swift
            let a = "<b>"
            ```

            text <b>bold</b> <br> www.example.com
            """
        let body = PreviewBody(markdown: markdown)
        #expect(body.html == MarkdownHTML.render(markdown, sourcePositions: true))
        // T, table, ordered list, task list with the raw HTML after it (raw HTML starts no block), code, text
        #expect(body.blocks.count == 6)
        #expect(!body.blocks[0].key.contains("data-sourcepos"))
        #expect(body.blocks[0].positions == ["1:1-1:3"])
    }

    @Test func changeKeepsStartAndEnd() {
        let old = PreviewBody(markdown: "a\n\nb\n\nc\n")
        let new = PreviewBody(markdown: "a\n\nb, edited\nmore\n\nc\n")
        let change = new.change(from: old, pageKnowsBlocks: false)
        #expect(change.count == 3 && change.start == 1 && change.removed == 1 && change.html.count == 1)
        #expect(change.positions == [2: ["6:1-6:1"]])
        #expect(change.starts == ["3:1-3:1", "5:1-5:1"])
        #expect(new.change(from: new, pageKnowsBlocks: true) == .init(count: 3, start: 3, removed: 0, html: [], positions: [:], starts: nil))
    }

    @Test func scanFollowsNesting() {
        var open: [String] = []
        #expect(PreviewBody.scan(#"<div title="a > b"><img src=x><br/><!-- <p> --></div>"#, open: &open) && open.isEmpty)
        #expect(PreviewBody.scan("<details><summary>s</summary>", open: &open) && open == ["details"])
        #expect(PreviewBody.scan("</details>", open: &open) && open.isEmpty)
        #expect(PreviewBody.scan("<svg><path d='M0'/></svg><style>p > a { }</style>", open: &open) && open.isEmpty)
        #expect(PreviewBody.scan("a < b <3", open: &open) && open.isEmpty)
        // Closed out of order, never closed, or a tag without an end: unsure.
        #expect(!PreviewBody.scan("<p><b>x</p>", open: &open))
        open = []
        #expect(!PreviewBody.scan("<!-- open", open: &open))
        #expect(!PreviewBody.scan("<a href=\"x", open: &open))
    }

    /// A web view with the preview page and our script, loaded.
    @MainActor
    private final class Page: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let style: DocumentStyle
        /// What the page shows, as the controller keeps it.
        private(set) var body: PreviewBody
        private var pageKnowsBlocks = false
        private var loaded: CheckedContinuation<Void, Never>?

        init(markdown: String, style: DocumentStyle) async throws {
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.userContentController.addUserScript(WKUserScript(
                source: PreviewRenderer.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
            webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), configuration: configuration)
            self.style = style
            let rendering = PreviewRenderer.render(markdown: markdown)
            body = rendering.body
            super.init()
            webView.navigationDelegate = self
            let html = PreviewRenderer.page(body: rendering.html, baseFolder: nil, style: style)
            await withCheckedContinuation { continuation in
                loaded = continuation
                webView.loadHTMLString(html, baseURL: nil)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                loaded?.resume()
                loaded = nil
            }
        }

        /// The number of blocks put in new.
        func update(_ markdown: String) async throws -> Int {
            let new = PreviewRenderer.render(markdown: markdown).body
            let change = new.change(from: body, pageKnowsBlocks: pageKnowsBlocks)
            body = new
            pageKnowsBlocks = true
            return try await send(change)
        }

        func send(_ change: PreviewBody.Change) async throws -> Int {
            let result = try await webView.callAsyncJavaScript(
                "return marcPreview.update(base, css, change)",
                arguments: ["base": "", "css": PreviewRenderer.stylesheet(style), "change": change.arguments],
                contentWorld: .defaultClient)
            return (result as? NSNumber)?.intValue ?? -2
        }

        func evaluate(_ script: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
            try await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: .defaultClient)
        }

        func headingIDs() async throws -> String {
            try await evaluate("return Array.from(document.querySelectorAll('h1, h2')).map(h => h.id).join(' ')") as? String ?? ""
        }

        func positions() async throws -> [String] {
            try await evaluate("return Array.from(document.querySelectorAll('[data-sourcepos]')).map(e => e.getAttribute('data-sourcepos'))")
                as? [String] ?? []
        }

        /// The body is the same as a page loaded with the current text (heading ids aside).
        func matchesFreshPage() async throws -> Bool {
            try await evaluate("""
                const fresh = document.createElement('main');
                fresh.innerHTML = html;
                const shown = document.getElementById('marc-body').cloneNode(true);
                for (const heading of shown.querySelectorAll('[id]')) heading.removeAttribute('id');
                return shown.innerHTML === fresh.innerHTML;
                """, ["html": body.html]) as? Bool ?? false
        }
    }
}
