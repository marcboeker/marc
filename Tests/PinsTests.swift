import Foundation
import Testing
@testable import Marcdown

/// The pin list, its persistence, and the sidebar order. Files are temporary; the defaults are an own suite.
@MainActor
struct PinsTests {
    private let suite = "PinsTests-\(UUID().uuidString)"
    private let folder = FileManager.default.temporaryDirectory.appending(path: "PinsTests-\(UUID().uuidString)")
    private let pins: Pins

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pins = Pins(defaults: UserDefaults(suiteName: suite)!, key: "pins")
    }

    private func make(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func open(_ url: URL) -> MarcdownFile {
        let file = MarcdownFile()
        file.fileURL = url
        return file
    }

    private func reload() -> Pins {
        Pins(defaults: UserDefaults(suiteName: suite)!, key: "pins")
    }

    @Test func pinsKeepTheirOrder() throws {
        let a = try make("a.md"), b = try make("b.md"), c = try make("c.md")
        pins.pin(b)
        pins.pin(c)
        pins.pin(a)
        #expect(pins.items.map(\.name) == ["b", "c", "a"])
    }

    @Test func aFileIsPinnedOnce() throws {
        let a = try make("a.md")
        pins.pin(a)
        pins.pin(a)
        #expect(pins.items.count == 1)
    }

    @Test func untitledAndMissingFilesCannotBePinned() {
        pins.pin(nil)
        pins.pin(folder.appending(path: "none.md"))
        #expect(pins.items.isEmpty)
    }

    @Test func pinsPersist() throws {
        let a = try make("a.md"), b = try make("b.md")
        pins.pin(a)
        pins.pin(b)
        let again = reload()
        #expect(again.items == pins.items)
        #expect(again.isPinned(a))
    }

    @Test func unpinRemovesAndPersists() throws {
        let a = try make("a.md"), b = try make("b.md")
        pins.pin(a)
        pins.pin(b)
        pins.unpin(try #require(pins.pin(for: a)))
        #expect(pins.items.map(\.name) == ["b"])
        #expect(reload().items.map(\.name) == ["b"])
    }

    @Test func togglePinSwitchesBetweenPinnedAndNot() throws {
        let file = open(try make("a.md"))
        let store = OpenFiles(pins: pins)
        store.togglePin(file)
        #expect(pins.isPinned(file.url))
        store.togglePin(file)
        #expect(!pins.isPinned(file.url))
        store.togglePin(MarcdownFile())
        #expect(pins.items.isEmpty)
    }

    @Test func resolveFollowsARename() throws {
        let a = try make("a.md")
        pins.pin(a)
        let renamed = folder.appending(path: "renamed.md")
        try FileManager.default.moveItem(at: a, to: renamed)
        let pin = try #require(pins.items.first)
        let resolved = try #require(pins.resolve(pin))
        #expect(Pins.key(resolved) == Pins.key(renamed))
        #expect(pins.items.map(\.name) == ["renamed"])
        #expect(reload().items.map(\.name) == ["renamed"])
    }

    @Test func resolveOfAMissingFileRemovesThePin() throws {
        let a = try make("a.md"), b = try make("b.md")
        pins.pin(a)
        pins.pin(b)
        try FileManager.default.removeItem(at: a)
        #expect(pins.resolve(pins.items[0]) == nil)
        #expect(pins.items.map(\.name) == ["b"])
        #expect(reload().items.map(\.name) == ["b"])
    }

    @Test func aPinFollowsAnOpenFileThatMoved() throws {
        let a = try make("a.md")
        pins.pin(a)
        let renamed = folder.appending(path: "renamed.md")
        try FileManager.default.moveItem(at: a, to: renamed)
        pins.fileMoved(from: a, to: renamed)
        #expect(pins.isPinned(renamed))
        #expect(!pins.isPinned(a))
    }

    @Test func aPinStaysWhenSaveAsCopiesTheFile() throws {
        let a = try make("a.md"), copy = try make("copy.md")
        pins.pin(a)
        pins.fileMoved(from: a, to: copy)
        #expect(pins.isPinned(a))
        #expect(!pins.isPinned(copy))
    }

    @Test func pinnedFileShowsOnlyInPinned() throws {
        let a = try make("a.md"), b = try make("b.md"), c = try make("c.md")
        let fileA = open(a), fileB = open(b), fileC = open(c)
        pins.pin(c)
        pins.pin(a)
        let store = OpenFiles(pins: pins)
        [fileA, fileB, fileC].forEach(store.show)
        let rows = store.sidebarRows
        #expect(rows.pinned.map(\.pin?.name) == ["c", "a"])
        #expect(rows.pinned.map(\.file) == [fileC, fileA])
        #expect(rows.open.map(\.file) == [fileB])
        #expect(rows.open.map(\.pin) == [nil])
        // A pinned row selects its pin, also when the file is open.
        #expect(rows.pinned.map(\.selection) == pins.items.map { .pin($0.id) })
        #expect(rows.open.map(\.selection) == [.file(fileB.id)])
    }

    @Test func closedPinHasNoFile() throws {
        let a = try make("a.md"), b = try make("b.md")
        let fileB = open(b)
        pins.pin(a)
        let store = OpenFiles(pins: pins)
        store.show(fileB)
        let rows = store.sidebarRows
        #expect(rows.pinned.count == 1)
        #expect(rows.pinned[0].file == nil)
        #expect(rows.pinned[0].displayName == "a")
        #expect(rows.pinned[0].url.map(Pins.key) == Pins.key(a))
        #expect(rows.open.map(\.file) == [fileB])
    }

    @Test func navigationOrderIsOpenPinsThenOthers() throws {
        let a = try make("a.md"), b = try make("b.md"), c = try make("c.md"), d = try make("d.md")
        let files = [open(a), open(b), open(c), open(d)]
        pins.pin(d)
        pins.pin(try make("closed.md"))
        pins.pin(b)
        let store = OpenFiles(pins: pins)
        files.forEach(store.show)
        #expect(store.sidebarOrder == [files[3], files[1], files[0], files[2]])
    }

    @Test func nextAndPreviousFollowSidebarOrder() throws {
        let a = try make("a.md"), b = try make("b.md"), c = try make("c.md")
        let files = [open(a), open(b), open(c)]
        pins.pin(c)
        let store = OpenFiles(pins: pins)
        files.forEach(store.show)
        store.selectedID = files[2].id
        store.selectNeighbor(1)
        #expect(store.selected === files[0])
        store.selectNeighbor(-1)
        #expect(store.selected === files[2])
        store.selectNeighbor(-1)
        #expect(store.selected === files[1])
    }

    @Test func closingSelectsTheNextOpenFileInSidebarOrder() throws {
        let a = try make("a.md"), b = try make("b.md"), c = try make("c.md")
        let files = [open(a), open(b), open(c)]
        pins.pin(c)
        pins.pin(try make("closed.md"))
        let store = OpenFiles(pins: pins)
        files.forEach(store.show)
        // Order: c, a, b.
        store.selectedID = files[2].id
        store.remove(files[2])
        #expect(store.selected === files[0])
        store.selectedID = files[1].id
        store.remove(files[1])
        #expect(store.selected === files[0])
    }

    @Test func closingTheLastRowSelectsTheOneAbove() throws {
        let a = try make("a.md"), b = try make("b.md")
        let files = [open(a), open(b)]
        pins.pin(b)
        let store = OpenFiles(pins: pins)
        files.forEach(store.show)
        // Order: b, a.
        store.selectedID = files[0].id
        store.remove(files[0])
        #expect(store.selected === files[1])
    }

    @Test func unpinningAnOpenFileMovesItToTheEndOfOpenFiles() throws {
        let a = try make("a.md"), b = try make("b.md")
        let files = [open(a), open(b)]
        pins.pin(a)
        let store = OpenFiles(pins: pins)
        files.forEach(store.show)
        store.unpin(try #require(pins.pin(for: a)))
        #expect(store.files == [files[1], files[0]])
        #expect(pins.items.isEmpty)
    }

    @Test func activatingAnOpenPinSelectsItsFile() throws {
        let a = try make("a.md"), b = try make("b.md")
        let files = [open(a), open(b)]
        pins.pin(a)
        let store = OpenFiles(pins: pins)
        files.forEach(store.show)
        store.activate(try #require(pins.pin(for: a)))
        #expect(store.selected === files[0])
    }

    @Test func activatingAMissingPinRemovesIt() throws {
        let a = try make("a.md")
        pins.pin(a)
        try FileManager.default.removeItem(at: a)
        let store = OpenFiles(pins: pins)
        store.activate(pins.items[0])
        #expect(pins.items.isEmpty)
        #expect(store.missingPinNotice?.message.contains("a") == true)
    }

    @Test func sidebarOpensWithPinsOrSeveralFiles() throws {
        let store = OpenFiles(pins: pins)
        #expect(!store.opensSidebar)
        let a = open(try make("a.md"))
        store.show(a)
        #expect(!store.opensSidebar)
        store.show(open(try make("b.md")))
        #expect(store.opensSidebar)
        store.remove(a)
        #expect(!store.opensSidebar)
        pins.pin(try make("c.md"))
        #expect(store.opensSidebar)
    }
}
