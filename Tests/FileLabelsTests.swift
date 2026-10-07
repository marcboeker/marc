import Foundation
import Testing
@testable import Marcdown

struct FileLabelsTests {
    private typealias Label = FileLabels.Label

    private func labels(_ entries: [(String?, String)]) -> [Label] {
        FileLabels.labels(for: entries.map { (url: $0.0.map { URL(filePath: $0) }, displayName: $0.1) })
    }

    @Test func uniqueNamesHaveNoFolder() {
        #expect(labels([("/a/one.md", ""), ("/b/two.markdown", ""), (nil, "Untitled")]) == [
            Label(name: "one", folder: nil),
            Label(name: "two", folder: nil),
            Label(name: "Untitled", folder: nil),
        ])
    }

    @Test func collidingNamesShowTheParentFolder() {
        #expect(labels([("/x/work/notes.md", ""), ("/x/home/notes.md", ""), ("/x/todo.md", "")]) == [
            Label(name: "notes", folder: "work"),
            Label(name: "notes", folder: "home"),
            Label(name: "todo", folder: nil),
        ])
    }

    @Test func sameExtensionlessNameWithAnotherExtensionCollides() {
        #expect(labels([("/a/notes.md", ""), ("/b/Notes.txt", "")]).map(\.folder) == ["a", "b"])
    }

    @Test func collidingParentsAddFoldersUntilUnique() {
        #expect(labels([("/p/a/x/n.md", ""), ("/p/b/x/n.md", ""), ("/p/c/n.md", "")]).map(\.folder) == [
            "a/x", "b/x", "c",
        ])
    }

    @Test func folderThatEndsAnotherPathShowsTheFullPath() {
        #expect(labels([("/a/n.md", ""), ("/b/a/n.md", "")]).map(\.folder) == ["/a", "b/a"])
    }

    @Test func untitledCollidingWithAFileHasNoFolder() {
        #expect(labels([(nil, "notes"), ("/a/notes.md", "")]) == [
            Label(name: "notes", folder: nil),
            Label(name: "notes", folder: "a"),
        ])
    }
}
