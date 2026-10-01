import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Marc

/// Per-file state and the outside-change policy for files the editor does not show.
@MainActor
struct MarcFileTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "MarcFileTests-\(UUID().uuidString)")

    private func makeFile(_ text: String) throws -> (MarcFile, URL) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "note.md")
        try Data(text.utf8).write(to: url)
        return (try MarcFile(contentsOf: url, ofType: UTType.markdown.identifier), url)
    }

    private func disk(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test func dirtyFollowsEditsAndClear() {
        let file = MarcFile()
        #expect(!file.isDirty)
        file.edit("text")
        #expect(file.isDirty)
        file.updateChangeCount(.changeCleared)
        #expect(!file.isDirty)
    }

    @Test func hiddenCleanFileTakesTheDiskText() throws {
        let (file, url) = try makeFile("old")
        try Data("new".utf8).write(to: url)
        file.reloader.fileChanged()
        #expect(file.text == "new")
        #expect(file.lastKnownDisk == "new")
        #expect(!file.isDirty)
        #expect(!file.needsDiskReview)
    }

    @Test func hiddenDirtyFileKeepsItsTextAndWaitsForReview() throws {
        let (file, url) = try makeFile("old")
        file.edit("old + mine")
        try Data("new".utf8).write(to: url)
        file.reloader.fileChanged()
        #expect(file.text == "old + mine")
        #expect(file.lastKnownDisk == "old")
        #expect(file.needsDiskReview)
    }

    @Test func outsideChangeBackToTheKnownTextEndsTheReview() throws {
        let (file, url) = try makeFile("old")
        file.edit("old + mine")
        try Data("new".utf8).write(to: url)
        file.reloader.fileChanged()
        try Data("old".utf8).write(to: url)
        file.reloader.fileChanged()
        #expect(!file.needsDiskReview)
    }

    @Test func autosaveWaitsForTheReview() async throws {
        let (file, url) = try makeFile("old")
        file.edit("old + mine")
        file.needsDiskReview = true
        let error = await withCheckedContinuation { continuation in
            file.autosave(withImplicitCancellability: false) { continuation.resume(returning: $0) }
        }
        #expect((error as? CocoaError)?.code == .userCancelled)
        #expect(try disk(url) == "old")
        #expect(file.isDirty)
    }

    @Test func saveMakesTheTextTheKnownDiskVersion() async throws {
        let (file, url) = try makeFile("old")
        file.edit("mine")
        let error = await withCheckedContinuation { continuation in
            file.save(to: url, ofType: UTType.markdown.identifier, for: .saveOperation) { continuation.resume(returning: $0) }
        }
        #expect(error == nil)
        #expect(try disk(url) == "mine")
        #expect(file.lastKnownDisk == "mine")
        #expect(!file.isDirty)
    }

    @Test func closingAFileWithAnOpenReviewShowsItInstead() async {
        let store = OpenFiles()
        let a = MarcFile(), b = MarcFile()
        [a, b].forEach(store.show)
        a.needsDiskReview = true
        #expect(await store.close(a) == false)
        #expect(store.files == [a, b])
        #expect(store.selected === a)
    }

    @Test func closingAllStopsAtAReviewBeforeClosingAnything() async {
        let store = OpenFiles()
        let a = MarcFile(), b = MarcFile()
        [a, b].forEach(store.show)
        b.needsDiskReview = true
        #expect(await store.closeAll() == false)
        #expect(store.files == [a, b])
        #expect(store.selected === b)
    }
}
