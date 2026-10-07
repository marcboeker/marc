import Foundation
import Testing
@testable import Marcdown
import Demark

struct LinkBuilderTests {
    let folder = URL(fileURLWithPath: "/tmp/notes/project")

    private func link(_ path: String, folder: URL? = URL(fileURLWithPath: "/tmp/notes/project")) -> String {
        LinkBuilder.link(for: URL(fileURLWithPath: path), documentFolder: folder)
    }

    @Test func sameFolder() { #expect(link("/tmp/notes/project/a.pdf") == "[a.pdf](a.pdf)") }
    @Test func subfolder() { #expect(link("/tmp/notes/project/assets/a.pdf") == "[a.pdf](assets/a.pdf)") }
    @Test func parentFolder() { #expect(link("/tmp/notes/a.pdf") == "[a.pdf](../a.pdf)") }
    @Test func siblingFolder() { #expect(link("/tmp/notes/other/x/a.pdf") == "[a.pdf](../other/x/a.pdf)") }
    @Test func unsavedIsAbsolute() { #expect(link("/tmp/notes/a.pdf", folder: nil) == "[a.pdf](/tmp/notes/a.pdf)") }
    @Test func rootOnlyCommonIsAbsolute() { #expect(link("/var/x/a.pdf") == "[a.pdf](/var/x/a.pdf)") }
    @Test func imageUsesBangAndBaseName() {
        #expect(link("/tmp/notes/project/img/cat.png") == "![cat](img/cat.png)")
        #expect(link("/tmp/notes/project/photo.JPEG") == "![photo](photo.JPEG)")
    }
    @Test func nonImage() { #expect(link("/tmp/notes/project/x.txt") == "[x.txt](x.txt)") }
    @Test func spacesUseAngleBrackets() {
        #expect(link("/tmp/notes/project/my file.png") == "![my file](<my file.png>)")
    }
    @Test func parenthesesUseAngleBrackets() {
        #expect(link("/tmp/notes/project/a(1).pdf") == "[a(1).pdf](<a(1).pdf>)")
    }
    @Test func directoryIsLikeFile() {
        let dir = URL(fileURLWithPath: "/tmp/notes/project/assets", isDirectory: true)
        #expect(LinkBuilder.link(for: dir, documentFolder: folder) == "[assets](assets)")
    }
    @Test func differentVolumeIsAbsolute() {
        let other = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes"))?
            .map { URL(fileURLWithPath: "/Volumes/\($0)") }
            .first { (try? $0.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject)?
                .isEqual((try? URL(fileURLWithPath: "/tmp").resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier) as? NSObject) == false }
        guard let other else { return }  // no second volume on this machine
        #expect(LinkBuilder.destination(for: other, documentFolder: folder) == other.path)
    }
    @Test func multipleFilesOnePerLine() {
        let urls = ["/tmp/notes/project/a.png", "/tmp/notes/project/b b.txt"].map { URL(fileURLWithPath: $0) }
        #expect(LinkBuilder.markdown(for: urls, documentFolder: folder) == "![a](a.png)\n[b b.txt](<b b.txt>)")
    }
}

struct PastePolicyTests {
    @Test func terminalStyledHTMLPrefersPlain() {
        let html = "<meta charset='utf-8'><span style=\"color: red\">let x = 1</span><br><span>print(x)</span>"
        #expect(PastePolicy.prefersPlainText(html: html, plain: "let x = 1\nprint(x)"))
    }
    @Test func entitiesAreDecoded() {
        #expect(PastePolicy.prefersPlainText(html: "<div>a &lt; b &amp;&amp; c</div>", plain: "a < b && c"))
    }
    @Test func semanticTagsConvert() {
        #expect(!PastePolicy.prefersPlainText(html: "<p>Hello <strong>world</strong></p>", plain: "Hello world"))
        #expect(!PastePolicy.prefersPlainText(html: "<a href='x'>link</a>", plain: "link"))
    }
    @Test func differentTextConverts() {
        #expect(!PastePolicy.prefersPlainText(html: "<p>Hello</p>", plain: "Something else"))
    }
    @Test func noPlainFlavorConverts() {
        #expect(!PastePolicy.prefersPlainText(html: "<p>Hello</p>", plain: nil))
    }
}

@MainActor
struct DemarkConversionTests {
    @Test func convertsCommonHTML() async throws {
        let html = "<h1>Title</h1><p>Some <strong>bold</strong> and <a href=\"https://x.com\">link</a>.</p><ul><li>one</li><li>two</li></ul>"
        let md = try await Demark().convertToMarkdown(html)
        #expect(md.contains("# Title"))
        #expect(md.contains("**bold**"))
        #expect(md.contains("[link](https://x.com)"))
        #expect(md.contains("- one"))
        #expect(md.contains("- two"))
    }
}
