import Foundation
import Testing
@testable import Marc

struct PreviewTests {
    private let style = PreviewStyle(fontFamily: "Iowan Old Style", fontSize: 17, lineSpacing: 4, maxWidth: 700)

    // MARK: Rendering

    @Test func previewCarriesSourcePositions() {
        let rendering = PreviewRenderer.render(markdown: "# T\n\nSome *text*.\n\n- a\n- b\n")
        #expect(rendering.html.contains("<h1 data-sourcepos=\"1:1-1:3\">T</h1>"))
        #expect(rendering.html.contains("<p data-sourcepos=\"3:1-3:12\">"))
        #expect(rendering.html.contains("<li data-sourcepos=\"6:1-6:3\">b</li>"))
    }

    @Test func printHasNoSourcePositions() {
        #expect(PrintRenderer.body(markdown: "# T\n") == "<h1>T</h1>\n")
        #expect(MarkdownHTML.render("# T\n") == PrintRenderer.body(markdown: "# T\n"))
    }

    @Test func previewFollowsDarkModeButPrintStaysLight() {
        let preview = PreviewRenderer.page(body: "<p>x</p>", baseFolder: nil, style: style)
        #expect(preview.contains("@media (prefers-color-scheme: dark)"))
        #expect(preview.contains("color-scheme: light dark"))
        let print = PrintRenderer.page(markdown: "x", title: "t", baseFolder: nil, fontFamily: nil)
        #expect(!print.contains("prefers-color-scheme"))
        #expect(!print.contains("data-sourcepos"))
        #expect(print.contains("html { color: #1d1d1f; background: white;"))
    }

    @Test func previewUsesEditorAppearance() {
        let css = PreviewRenderer.stylesheet(style)
        #expect(css.contains("font-family: \"Iowan Old Style\", -apple-system"))
        #expect(css.contains("font-size: 17px"))
        #expect(css.contains("--extra-line: 4px"))
        #expect(css.contains("main { max-width: 700px; margin: 0 auto; }"))
        let full = PreviewRenderer.stylesheet(PreviewStyle(fontFamily: nil, fontSize: 15, lineSpacing: 2, maxWidth: nil))
        #expect(full.contains("font-family: -apple-system"))
        #expect(full.contains("main { margin: 0 auto; }"))
    }

    @Test func pageSetsBaseFolder() {
        let folder = URL(filePath: "/Users/me/My Notes/", directoryHint: .isDirectory)
        let page = PreviewRenderer.page(body: "", baseFolder: folder, style: style)
        #expect(page.contains("<base href=\"marc-preview://file/Users/me/My%20Notes/\">"))
        #expect(page.contains("<main id=\"marc-body\">"))
        #expect(!PreviewRenderer.page(body: "", baseFolder: nil, style: style).contains("<base"))
    }

    // MARK: Source map

    @Test func sourceMapReadsPositions() {
        let map = PreviewSourceMap(html: PreviewRenderer.render(markdown: "# A\n\npara\nline two\n").html)
        #expect(map.blocks == [
            .init(position: "1:1-1:3", lines: 1...1),
            .init(position: "3:1-4:8", lines: 3...4),
        ])
    }

    @Test func targetIsInnermostBlockWithTheLine() {
        // 1 # A, 3 > quote, 4 > - item, 6 para
        let map = PreviewRenderer.render(markdown: "# A\n\n> quote\n> - item\n\npara\n").sourceMap
        #expect(map.target(forEditorLine: 1)?.position == "1:1-1:3")
        #expect(map.target(forEditorLine: 4)?.position == "4:3-4:8")   // the list item, not the quote
        #expect(map.target(forEditorLine: 6) == .init(position: "6:1-6:4", fraction: 0))
    }

    @Test func targetBetweenBlocksIsTheNextBlock() {
        let map = PreviewRenderer.render(markdown: "a\n\n\n\nb\n").sourceMap
        #expect(map.target(forEditorLine: 3) == .init(position: "5:1-5:1", fraction: 0))
        #expect(map.target(forEditorLine: 99) == .init(position: "5:1-5:1", fraction: 1))
        #expect(PreviewSourceMap(html: "").target(forEditorLine: 1) == nil)
    }

    @Test func targetFractionInsideLongBlock() {
        let map = PreviewRenderer.render(markdown: "```\n1\n2\n3\n```\n").sourceMap   // lines 1–5
        #expect(map.target(forEditorLine: 1)?.fraction == 0)
        #expect(map.target(forEditorLine: 3)?.fraction == 0.4)
    }

    @Test func frontMatterShiftsLines() {
        let map = PreviewRenderer.render(markdown: "---\ntitle: x\n---\n\n# T\n").sourceMap
        #expect(map.frontMatterLines == 4)
        #expect(map.target(forEditorLine: 5)?.position == "1:1-1:3")
        #expect(map.target(forEditorLine: 2)?.position == "1:1-1:3")   // inside front matter: the top
    }

    @Test func lineAtOffset() {
        let map = PreviewRenderer.render(markdown: "ab\ncd\r\n\nü").sourceMap
        #expect(map.line(atUTF16Offset: 0) == 1)
        #expect(map.line(atUTF16Offset: 2) == 1)
        #expect(map.line(atUTF16Offset: 3) == 2)
        #expect(map.line(atUTF16Offset: 7) == 3)
        #expect(map.line(atUTF16Offset: 100) == 4)
        #expect(PreviewSourceMap(html: "").line(atUTF16Offset: 5) == 1)
    }

    // MARK: Modes

    @Test func modeToggles() {
        #expect(PreviewMode.editor.toggled(.overlay) == .overlay)
        #expect(PreviewMode.editor.toggled(.split) == .split)
        #expect(PreviewMode.overlay.toggled(.overlay) == .editor)
        #expect(PreviewMode.split.toggled(.split) == .editor)
        #expect(PreviewMode.overlay.toggled(.split) == .split)   // the other key switches directly
        #expect(PreviewMode.split.toggled(.overlay) == .overlay)
    }

    @Test func splitLayout() {
        let half = PreviewLayout(mode: .split, width: 1001, fraction: 0.5)
        #expect((half.editorWidth, half.previewX, half.previewWidth) == (500, 501, 500))
        let overlay = PreviewLayout(mode: .overlay, width: 800, fraction: 0.5)
        #expect((overlay.editorWidth, overlay.previewX, overlay.previewWidth) == (800, 0, 800))
        #expect(PreviewLayout(mode: .split, width: 1001, fraction: 0.1).editorWidth == 280)
        #expect(PreviewLayout(mode: .split, width: 1001, fraction: 0.9).previewWidth == 280)
        #expect(PreviewLayout(mode: .split, width: 401, fraction: 0.8).editorWidth == 200)   // too narrow: equal halves
        #expect(PreviewLayout.fraction(dividerAt: 100, width: 1001) == 0.28)
        #expect(PreviewLayout.fraction(dividerAt: 600, width: 1001) == 0.6)
    }

    // MARK: Links

    private let folder = URL(filePath: "/Users/me/Notes/", directoryHint: .isDirectory)

    /// A link as the page resolves it against `<base href>`.
    private func resolved(_ href: String, base: URL? = nil) -> URL {
        URL(string: href, relativeTo: URL(string: PreviewScheme.base(base ?? folder))!)!.absoluteURL
    }

    @Test func linkToMarkdownFileOpensInMarc() {
        #expect(PreviewLink.classify(resolved("other%20note.md#part"), baseFolder: folder) == .markdownFile(URL(filePath: "/Users/me/Notes/other note.md")))
        #expect(PreviewLink.classify(resolved("../Up.MARKDOWN"), baseFolder: folder) == .markdownFile(URL(filePath: "/Users/me/Up.MARKDOWN")))
        #expect(PreviewLink.classify(resolved("/a/b.md"), baseFolder: folder) == .markdownFile(URL(filePath: "/a/b.md")))
        #expect(PreviewLink.classify(URL(filePath: "/a/B.md"), baseFolder: folder) == .markdownFile(URL(filePath: "/a/B.md")))
        // The same Markdown rule as a drop on the sidebar (`URL.isMarkdownFile`), but plain text shows in Finder.
        #expect(PreviewLink.classify(resolved("c.txt"), baseFolder: folder) == .localFile(URL(filePath: "/Users/me/Notes/c.txt")))
    }

    @Test func otherLocalFilesShowInFinder() {
        #expect(PreviewLink.classify(resolved("run.command"), baseFolder: folder) == .localFile(URL(filePath: "/Users/me/Notes/run.command")))
        #expect(PreviewLink.classify(resolved("a.pdf?x=1"), baseFolder: folder) == .localFile(URL(filePath: "/Users/me/Notes/a.pdf")))
        let app = URL(filePath: "/Applications/Calculator.app", directoryHint: .isDirectory)
        #expect(PreviewLink.classify(app, baseFolder: folder) == .localFile(app))
    }

    @Test func webAndMailLinksGoToTheDefaultApp() {
        let web = URL(string: "https://swift.org/#top")!
        #expect(PreviewLink.classify(web, baseFolder: folder) == .web(web))
        let mail = URL(string: "mailto:a@b.c")!
        #expect(PreviewLink.classify(mail, baseFolder: folder) == .web(mail))
        #expect(PreviewLink.classify(URL(string: "vnc://host")!, baseFolder: folder) == .ignored)
        #expect(PreviewLink.classify(URL(string: "javascript:alert(1)")!, baseFolder: folder) == .ignored)
    }

    @Test func fragmentLinksScrollThePreview() {
        #expect(PreviewLink.classify(resolved("#my-heading"), baseFolder: folder) == .anchor("my-heading"))
        let unsaved = URL(string: "#x", relativeTo: PreviewScheme.pageURL)!.absoluteURL
        #expect(PreviewLink.classify(unsaved, baseFolder: nil) == .anchor("x"))
        // An unsaved document has no folder for relative links.
        let relative = URL(string: "a.md", relativeTo: PreviewScheme.pageURL)!.absoluteURL
        #expect(PreviewLink.classify(relative, baseFolder: nil) == .ignored)
        // A fragment in another folder is not this document.
        let other = resolved("../Other/#x")
        #expect(PreviewLink.classify(other, baseFolder: folder) == .localFile(URL(filePath: "/Users/me/Other/", directoryHint: .isDirectory)))
    }

    // MARK: Scheme

    @Test func schemeMapsFiles() {
        #expect(PreviewScheme.base(URL(filePath: "/Users/me/My Notes", directoryHint: .isDirectory)) == "marc-preview://file/Users/me/My%20Notes/")
        #expect(PreviewScheme.base(nil) == "")
        #expect(PreviewScheme.fileURL(resolved("sub/a%20b.png")) == URL(filePath: "/Users/me/Notes/sub/a b.png"))
        #expect(PreviewScheme.fileURL(PreviewScheme.pageURL) == nil)
        #expect(PreviewScheme.fileURL(URL(string: "https://file/x")!) == nil)
    }

    @Test func schemeGivesOutOnlyTheDocumentFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MarcSchemeTest-\(UUID().uuidString)")
        let folder = root.appending(path: "doc", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "out"), withDestinationURL: root)
        try Data("x".utf8).write(to: root.appending(path: "secret.png"))
        let inside = folder.appending(path: "sub/a.png")
        #expect(PreviewScheme.allowed(inside, in: folder) != nil)
        #expect(PreviewScheme.allowed(folder.appending(path: "../secret.png"), in: folder) == nil)
        #expect(PreviewScheme.allowed(folder.appending(path: "out/secret.png"), in: folder) == nil)   // symlink out
        #expect(PreviewScheme.allowed(root.appending(path: "docs/x.png"), in: folder) == nil)       // prefix, not a folder
        #expect(PreviewScheme.allowed(inside, in: nil) == nil)
        // The read off the main thread keeps the same rule.
        let rootPath = try #require(PreviewScheme.root(folder))
        try Data("png".utf8).write(to: inside)
        #expect(PreviewScheme.read(inside, root: rootPath)?.data == Data("png".utf8))
        #expect(PreviewScheme.read(inside, root: rootPath)?.mimeType == "image/png")
        #expect(PreviewScheme.read(folder.appending(path: "out/secret.png"), root: rootPath) == nil)
        // `#name` through a symlink to the document folder is still this document.
        let link = URL(string: PreviewScheme.base(folder.appending(path: "out/doc", directoryHint: .isDirectory)) + "#x")!
        #expect(PreviewLink.classify(link, baseFolder: folder) == .anchor("x"))
    }
}
