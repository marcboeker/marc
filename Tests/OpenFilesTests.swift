import Foundation
import Testing
@testable import Marc

/// The store's list and selection rules. Files are bare MarcFile objects: no AppKit document list, no window.
@MainActor
struct OpenFilesTests {
    private let store = OpenFiles(pins: Pins(defaults: UserDefaults(suiteName: "OpenFilesTests-\(UUID().uuidString)")!, key: "pins"))
    private let a = MarcFile(), b = MarcFile(), c = MarcFile()

    private func showAll() {
        [a, b, c].forEach(store.show)
    }

    @Test func showAddsAtBottomAndSelects() {
        showAll()
        #expect(store.files == [a, b, c])
        #expect(store.selected === c)
    }

    @Test func showingAnOpenFileSelectsItWithoutAddingIt() {
        showAll()
        store.show(a)
        #expect(store.files == [a, b, c])
        #expect(store.selected === a)
    }

    @Test func removingSelectedFileSelectsTheOneBelow() {
        showAll()
        store.selectedID = b.id
        store.remove(b)
        #expect(store.files == [a, c])
        #expect(store.selected === c)
    }

    @Test func removingSelectedLastFileSelectsTheOneAbove() {
        showAll()
        store.remove(c)
        #expect(store.selected === b)
    }

    @Test func removingAnotherFileKeepsTheSelection() {
        showAll()
        store.remove(a)
        #expect(store.selected === c)
    }

    @Test func removingTheOnlyFileLeavesNoSelection() {
        store.show(a)
        store.remove(a)
        #expect(store.files.isEmpty)
        #expect(store.selectedID == nil)
    }

    @Test func neighborsWrapAround() {
        showAll()
        store.selectNeighbor(1)
        #expect(store.selected === a)
        store.selectNeighbor(-1)
        #expect(store.selected === c)
        store.selectNeighbor(-1)
        #expect(store.selected === b)
    }

    @Test func emptyUntitledFileClosesWithoutAQuestion() async {
        #expect(!a.asksBeforeClosing)
        #expect(await a.canClose())
    }

    @Test func untitledFileWithTextAsks() {
        a.edit("draft")
        #expect(a.asksBeforeClosing)
    }

    @Test func editMarksTheFileChanged() {
        a.edit("# Title")
        #expect(a.text == "# Title")
        #expect(a.isDocumentEdited)
    }
}
