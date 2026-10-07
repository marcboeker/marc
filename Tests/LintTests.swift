import Foundation
import Testing
@testable import Marcdown

@Suite struct LintTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.md", "my file.md", "img.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
    }

    private func lines(_ text: String, folder: URL? = nil) -> [Int] {
        lint(text, documentFolder: folder ?? self.folder).map(\.line)
    }

    @Test func existingLinkIsFine() { #expect(lines("[x](a.md)") == []) }
    @Test func missingLinkFlagged() { #expect(lines("ok\n\n[x](nope.md)") == [3]) }
    @Test func missingImageFlagged() { #expect(lines("![x](missing.png)") == [1]) }
    @Test func existingImageFine() { #expect(lines("![x](img.png)") == []) }
    @Test func fragmentAndQueryStripped() {
        #expect(lines("[x](a.md#top) [y](a.md?v=1) [z](nope.md#top)") == [1])
        #expect(lines("[x](a.md#top)") == [])
    }
    @Test func anchorOnlyIgnored() { #expect(lines("[x](#section)") == []) }
    @Test func angleBracketPathWithSpaces() {
        #expect(lines("[x](<my file.md>)") == [])
        #expect(lines("[x](<other file.md>)") == [1])
    }
    @Test func percentEncoding() {
        #expect(lines("[x](my%20file.md)") == [])
        #expect(lines("[x](gone%20file.md)") == [1])
    }
    @Test func remoteAndMailIgnored() {
        #expect(lines("[a](https://example.com/x) [b](mailto:a@b.c) <https://example.com> [c](//cdn.x/y)") == [])
    }
    @Test func unsavedDocumentSkipsRelative() {
        #expect(lint("[x](nope.md)", documentFolder: nil).isEmpty)
    }
    @Test func absolutePathsCheckedWhenUnsaved() {
        #expect(lint("[x](/definitely/not/here.md)", documentFolder: nil).count == 1)
        #expect(lint("[x](file:///definitely/not/here.md)", documentFolder: nil).count == 1)
        #expect(lint("[x](\(folder.appendingPathComponent("a.md").path))", documentFolder: nil).isEmpty)
    }

    @Test func headingJump() {
        #expect(lines("# A\n\n### B") == [3])
        #expect(lint("# A\n\n### B", documentFolder: nil).first?.message.contains("H1") == true)
    }
    @Test func headingNoJump() {
        #expect(lines("# A\n## B\n### C\n# D\n## E") == [])
        #expect(lines("### First\n#### Second") == [])
        #expect(lines("### A\n# B\n## C") == [])
    }

    @Test func frontMatterSkippedWithLineNumbers() {
        let text = "---\ntitle: [x](nope.md)\n# not heading\n---\n# A\n\n[x](nope.md)\n### B"
        #expect(lines(text) == [7, 8])
        #expect(lines("---\ntitle: x\n...\n[x](nope.md)") == [4])
    }
    @Test func unclosedFrontMatterIsNotFrontMatter() {
        #expect(lines("---\n[x](nope.md)") == [2])
    }
    @Test func dashesNotAtStartAreNotFrontMatter() {
        #expect(lines("text\n\n---\n[x](nope.md)\n---") == [4])
    }
}
