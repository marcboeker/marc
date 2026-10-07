import AppKit
import Testing
@testable import Marcdown

/// The palette's pure logic: fuzzy match, shortcut text, menu walk, refresh, lookup and exclusions, recency,
/// ranking, selection, files.
/// Menus are built by hand (no main menu), files and pins are temporary, the defaults are an own suite.
@MainActor
struct CommandPaletteTests {
    private let suite = "CommandPaletteTests-\(UUID().uuidString)"
    private let folder = FileManager.default.temporaryDirectory.appending(path: "CommandPaletteTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Fuzzy match

    @Test func subsequencesMatchIgnoringCaseAndSpaces() {
        #expect(FuzzyMatch.score("tl", "Task List") != nil)
        #expect(FuzzyMatch.score("nf", "Next File") != nil)
        #expect(FuzzyMatch.score("NEXT file", "Next File") != nil)
        #expect(FuzzyMatch.score("", "Anything") == 0)
    }

    @Test func nonSubsequencesDoNotMatch() {
        #expect(FuzzyMatch.score("lk", "Task List") == nil)
        #expect(FuzzyMatch.score("xyz", "Next File") == nil)
        #expect(FuzzyMatch.score("previews", "Preview") == nil)
    }

    @Test func prefixBeatsWordStartBeatsScattered() throws {
        let prefix = try #require(FuzzyMatch.score("si", "Side by Side"))
        let wordStart = try #require(FuzzyMatch.score("si", "Show Sidebar"))
        let scattered = try #require(FuzzyMatch.score("si", "Paste as Plain Text"))
        #expect(prefix > wordStart)
        #expect(wordStart > scattered)
    }

    @Test func wordStartsAndRunsWin() throws {
        // "tl": the word starts of Task List, not the scattered letters of "Bulleted List" or "Strikethrough".
        #expect(try #require(FuzzyMatch.score("tl", "Task List")) > (FuzzyMatch.score("tl", "Bulleted List") ?? .min))
        #expect(try #require(FuzzyMatch.score("nf", "Next File")) > (FuzzyMatch.score("nf", "Install Command Line Tool…") ?? .min))
        // A run of letters beats the same letters apart.
        #expect(try #require(FuzzyMatch.score("code", "Code Block")) > (FuzzyMatch.score("code", "Create Order Detail Entry") ?? .min))
    }

    @Test func shorterTitleWinsAnEqualMatch() throws {
        #expect(try #require(FuzzyMatch.score("prv", "Preview")) > (try #require(FuzzyMatch.score("prv", "Previous File"))))
    }

    // MARK: Shortcut display

    @Test func shortcutsUseMacOSModifierOrder() {
        #expect(PaletteItem.shortcut(key: "p", modifiers: [.command, .control]) == "⌃⌘P")
        #expect(PaletteItem.shortcut(key: "[", modifiers: [.command, .shift]) == "⇧⌘[")
        #expect(PaletteItem.shortcut(key: "+", modifiers: .command) == "⌘+")
        #expect(PaletteItem.shortcut(key: "f", modifiers: [.shift, .option, .command, .control]) == "⌃⌥⇧⌘F")
        #expect(PaletteItem.shortcut(key: "", modifiers: .command) == "")
    }

    @Test func uppercaseLetterImpliesShift() {
        #expect(PaletteItem.shortcut(key: "T", modifiers: .command) == "⇧⌘T")
        #expect(PaletteItem.shortcut(key: "T", modifiers: [.command, .shift]) == "⇧⌘T")
    }

    @Test func specialKeysHaveSymbols() {
        #expect(PaletteItem.shortcut(key: "\r", modifiers: .command) == "⌘↩")
        #expect(PaletteItem.shortcut(key: String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!), modifiers: .option) == "⌥↑")
        #expect(PaletteItem.shortcut(key: String(UnicodeScalar(UInt16(NSF5FunctionKey))!), modifiers: []) == "F5")
        #expect(PaletteItem.shortcut(key: "f", modifiers: .function) == "fn F")
        #expect(PaletteItem.shortcut(key: String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!), modifiers: [.function, .command]) == "⌘↑")
    }

    // MARK: Menu walk

    /// Target for the hand-built menu items; any action works, the palette never runs them here.
    private final class Target: NSObject {
        @objc func act(_ sender: Any?) {}
    }

    private let target = Target()

    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false   // isEnabled is what the test sets
        items.forEach(menu.addItem)
        let owner = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        owner.submenu = menu
        return owner
    }

    private func item(_ title: String, _ action: String = "act:", key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.isEnabled = enabled
        return item
    }

    private func mainMenu() -> NSMenu {
        let hidden = item("Toggle Sidebar")
        hidden.isHidden = true
        let alternate = item("Close All", key: "w", [.command, .option])
        alternate.isAlternate = true
        let bar = NSMenu(title: "Main")
        bar.autoenablesItems = false
        [
            menu("Marcdown", [
                item("About Marcdown", "orderFrontStandardAboutPanel:"),
                item("Settings…", key: ","),
                .separator(),
                menu("Services", [item("Make Sticky", key: "Y")]),
                item("Hide Marcdown", "hide:", key: "h"),
                item("Hide Others", "hideOtherApplications:", key: "h", [.command, .option]),
                item("Quit Marcdown", "terminate:", key: "q"),
            ]),
            menu("File", [
                item("New", key: "n"),
                menu("Open Recent", [item("a.md"), item("Clear Menu", "clearRecentDocuments:")]),
                item("Close", key: "w"),
                alternate,
                item("Save", key: "s", enabled: false),
                item("Unpin File", key: "d"),
            ]),
            menu("Edit", [
                item("Undo Typing", "undo:", key: "z"),
                item("Copy", "copy:", key: "c"),
                item("Paste and Match Style", "pasteAsPlainText:", key: "v", [.command, .option, .shift]),
                .separator(),
                menu("Find", [item("Find…", key: "f"), item("Find Next", key: "g")]),
                menu("AutoFill", [item("Contact…", "_handleInsertFromContactsCommand:")]),
                item("Start Dictation", "startDictation:"),
                item("Emoji & Symbols", "orderFrontCharacterPalette:", key: " ", [.command, .control]),
            ]),
            menu("View", [hidden, item("Show Sidebar", "toggleSidebar:", key: "s", [.command, .control]),
                          item("Exit Full Screen", "toggleFullScreen:", key: "f", [.command, .control])]),
            menu("Window", [
                item("Minimize", "performMiniaturize:", key: "m"),
                item("Zoom", "performZoom:"),
                item("Fill", "_zoomFill:"),
                item("Previous File", key: "[", [.command, .shift]),
                item("notes", key: "1", [.command, .option]),
                item("Bring All to Front", "arrangeInFront:"),
            ]),
            menu("Help", [item("Marcdown Help", "showHelp:", key: "?")]),
        ].forEach(bar.addItem)
        return bar
    }

    @Test func commandsSkipSystemDisabledHiddenAndSeparators() {
        let commands = PaletteItems.commands(in: mainMenu())
        #expect(commands.map(\.title) == [
            "Settings…", "New", "Close", "Unpin File", "Find…", "Find Next", "Show Sidebar", "Exit Full Screen",
            "Previous File",
        ])
    }

    @Test func commandsCarryPathKeysAndShortcuts() throws {
        let commands = PaletteItems.commands(in: mainMenu())
        #expect(commands.map(\.id) == [
            "Marcdown/Settings…", "File/New", "File/Close", "File/Pin File", "Edit/Find/Find…", "Edit/Find/Find Next",
            "View/Show Sidebar", "View/Enter Full Screen", "Window/Previous File",
        ])
        #expect(commands.map(\.shortcut) == ["⌘,", "⌘N", "⌘W", "⌘D", "⌘F", "⌘G", "⌃⌘S", "⌃⌘F", "⇧⌘["])
        #expect(commands.map(\.category) == ["App", "Document", "Document", "Document", "Find", "Find", "View", "View", "Go"])
        let find = try #require(commands.first { $0.title == "Find…" })
        guard case .menu(let path) = find.action else { Issue.record("not a menu item"); return }
        #expect(path == MenuPath(titles: ["Edit", "Find", "Find…"], keyEquivalent: "f", modifiers: .command))
    }

    @Test func exclusionUsesSelectorsBeforeTitles() {
        // Renamed system items still go by their selector; an own item with a system title goes by its title.
        #expect(MenuExclusion.excludes(item("Quit Everything", "terminate:")))
        #expect(MenuExclusion.excludes(item("Undo Bold", "undo:")))
        #expect(MenuExclusion.excludes(item("Tile Left", "_zoomLeft:")))
        #expect(MenuExclusion.excludes(item("Bring All to Front")))
        #expect(!MenuExclusion.excludes(item("Enter Full Screen", "toggleFullScreen:")))
        #expect(!MenuExclusion.excludes(item("Settings…")))
        #expect(!MenuExclusion.excludes(item("Bigger", key: "+")))
        #expect(MenuExclusion.excludes(item("Select All", "selectAll:", key: "a")))
        #expect(MenuExclusion.excludes(item(CommandLauncher.menuTitle, key: "P")))
    }

    @Test func categoriesGoByTitleThenMenu() {
        #expect(PaletteItem.category(of: ["File", "Print…"]) == "Print")
        #expect(PaletteItem.category(of: ["File", "Save"]) == "Document")
        #expect(PaletteItem.category(of: ["View", "Bigger"]) == "Text Size")
        #expect(PaletteItem.category(of: ["View", "Preview"]) == "View")
        #expect(PaletteItem.category(of: ["Format", "Bold"]) == "Format")
        #expect(PaletteItem.category(of: ["Edit", "Find", "Find Next"]) == "Find")
        #expect(PaletteItem.category(of: ["Window", "Next File"]) == "Go")
        #expect(PaletteItem.category(of: ["Marcdown", "Settings…"]) == "App")
        #expect(PaletteItem.category(of: ["Tools", "Word Count"]) == "Tools")   // a new menu names itself
    }

    @Test func toggledTitlesShareAKey() {
        let pin = item("Pin File"), unpin = item("Unpin File")
        let bar = NSMenu(title: "Main")   // kept alive: a menu holds its supermenu weakly
        bar.addItem(menu("File", [pin, unpin]))
        #expect(PaletteItem.key(for: pin) == "File/Pin File")
        #expect(PaletteItem.key(for: unpin) == "File/Pin File")
        #expect(PaletteItem.key(for: item("Hide Sidebar")) == "Show Sidebar")
        withExtendedLifetime(bar) {}
    }

    /// Stands in for SwiftUI's menu delegate: the item is only right after `menuNeedsUpdate`.
    private final class StaleMenu: NSObject, NSMenuDelegate {
        var updated = 0
        func menuNeedsUpdate(_ menu: NSMenu) {
            updated += 1
            menu.items[0].isEnabled = true
            menu.items[0].title = "Hide Sidebar"
        }
    }

    @Test func refreshAsksTheMenuDelegatesFirst() {
        let stale = StaleMenu()
        let view = menu("View", [item("Show Sidebar", key: "s", [.command, .control], enabled: false)])
        view.submenu?.delegate = stale
        let bar = NSMenu(title: "Main")
        bar.addItem(view)
        let commands = PaletteItems.commands(in: bar)
        #expect(stale.updated == 1)
        #expect(commands.map(\.title) == ["Hide Sidebar"])
        #expect(commands.map(\.id) == ["View/Show Sidebar"])
    }

    @Test func lookupFindsTheLiveItemByPath() throws {
        let bar = mainMenu()
        let path = MenuPath(try #require(bar.items[2].submenu?.items[4].submenu?.items[0]))   // Edit > Find > Find…
        #expect(path.titles == ["Edit", "Find", "Find…"])
        // SwiftUI put in a new object: the lookup finds the new one.
        let find = try #require(bar.items[2].submenu?.items[4].submenu)
        let replacement = item("Find…", key: "f")
        find.removeItem(at: 0)
        find.insertItem(replacement, at: 0)
        #expect(PaletteItems.item(at: path, in: bar) === replacement)
        #expect(PaletteItems.item(at: MenuPath(titles: ["Edit", "Find", "Gone"]), in: bar) == nil)
        #expect(PaletteItems.item(at: MenuPath(titles: ["Nope", "Find…"]), in: bar) == nil)
    }

    @Test func lookupFollowsToggledTitlesAndShortcuts() throws {
        let bar = mainMenu()
        let view = try #require(bar.items[3].submenu)
        // Path taken as "Show Sidebar"; the item reads "Hide Sidebar" now. The hidden duplicate is skipped.
        let sidebar = view.items[1]
        let path = MenuPath(sidebar)
        sidebar.title = "Hide Sidebar"
        view.items[0].title = "Hide Sidebar"
        #expect(PaletteItems.item(at: path, in: bar) === sidebar)
        // Same title twice: the shortcut tells them apart.
        let other = item("Hide Sidebar", key: "s", [.command, .option])
        view.insertItem(other, at: 1)
        #expect(PaletteItems.item(at: path, in: bar) === sidebar)
        #expect(PaletteItems.item(at: MenuPath(other), in: bar) === other)
    }

    // MARK: Recency

    @Test func sentMenuItemsGiveRecencyKeys() throws {
        let bar = mainMenu()
        let file = try #require(bar.items[1].submenu)
        let window = try #require(bar.items[4].submenu)
        let launcher = item(CommandLauncher.menuTitle, key: "P")
        try #require(bar.items[3].submenu).addItem(launcher)
        #expect(PaletteItems.recencyKey(for: file.items[0]) == "File/New")
        #expect(PaletteItems.recencyKey(for: file.items[5]) == "File/Pin File")             // Unpin File
        #expect(PaletteItems.recencyKey(for: file.items[1].submenu!.items[0]) == nil)        // Open Recent > a.md
        #expect(PaletteItems.recencyKey(for: window.items[4]) == nil)                        // a pin, ⌥⌘1
        #expect(PaletteItems.recencyKey(for: window.items[0]) == nil)                        // Minimize
        #expect(PaletteItems.recencyKey(for: launcher) == nil)
    }

    private func recency(limit: Int = 50) -> CommandRecency {
        CommandRecency(defaults: UserDefaults(suiteName: suite)!, limit: limit)
    }

    @Test func recordPutsTheKeyInFront() {
        let store = recency()
        store.record("File/New")
        store.record("View/Preview")
        store.record("File/New")
        #expect(store.keys == ["File/New", "View/Preview"])
    }

    @Test func recencyIsCapped() {
        let store = recency(limit: 3)
        ["a", "b", "c", "d"].forEach(store.record)
        #expect(store.keys == ["d", "c", "b"])
    }

    @Test func recencyPersists() {
        recency().record("Format/Bold")
        recency().record("Format/Italic")
        #expect(recency().keys == ["Format/Italic", "Format/Bold"])
    }

    // MARK: Ranking

    private func entry(_ id: String, _ title: String? = nil, category: String = "") -> PaletteItem {
        PaletteItem(id: id, category: category, title: title ?? id, shortcut: "", action: .menu(MenuPath(titles: [id])))
    }

    @Test func queryAlsoMatchesThePrefix() {
        let commands = [entry("Format/Bold", "Bold", category: "Format"), entry("View/Preview", "Preview", category: "View"),
                        entry("Format/Italic", "Italic", category: "Format")]
        let ranked = PaletteRanking.rank(files: [], commands: commands, query: "format", recency: [])
        #expect(ranked.map(\.id) == ["Format/Bold", "Format/Italic"])
        // The title alone still counts: the prefix does not lower a title match.
        let bold = PaletteRanking.rank(files: [], commands: commands, query: "bold", recency: [])
        #expect(bold.map(\.id) == ["Format/Bold"])
    }

    @Test func emptyQueryPutsRecentFirstThenFilesThenCommands() {
        let files = [entry("/a.md", "a"), entry("/b.md", "b"), entry("/pin.md", "pin")]
        let commands = [entry("New"), entry("Close"), entry("Bold")]
        let ranked = PaletteRanking.rank(files: files, commands: commands, query: " ", recency: ["Bold", "/b.md", "gone"])
        #expect(ranked.map(\.id) == ["Bold", "/b.md", "/a.md", "/pin.md", "New", "Close"])
    }

    @Test func queryRanksByScoreOnly() {
        let commands = [entry("Previous File"), entry("Preview"), entry("Task List"), entry("Bulleted List")]
        let ranked = PaletteRanking.rank(files: [], commands: commands, query: "prv", recency: ["Previous File"])
        #expect(ranked.map(\.id) == ["Preview", "Previous File"])   // recency does not beat a better score
        #expect(PaletteRanking.rank(files: [], commands: commands, query: "tl", recency: []).first?.id == "Task List")
    }

    @Test func recencyBreaksTiesThenBaseOrder() {
        let files = [entry("/x/Notes.md", "Notes")]
        let commands = [entry("Edit/Notes", "Notes"), entry("View/Notes", "Notes")]
        #expect(PaletteRanking.rank(files: files, commands: commands, query: "notes", recency: [])
            .map(\.id) == ["/x/Notes.md", "Edit/Notes", "View/Notes"])
        #expect(PaletteRanking.rank(files: files, commands: commands, query: "notes", recency: ["View/Notes"])
            .map(\.id) == ["View/Notes", "/x/Notes.md", "Edit/Notes"])
    }

    // MARK: Selection

    @Test func selectionWrapsAtTheEnds() {
        #expect(CommandLauncher.index(0, movedBy: -1, count: 5) == 4)
        #expect(CommandLauncher.index(4, movedBy: 1, count: 5) == 0)
        #expect(CommandLauncher.index(2, movedBy: 1, count: 5) == 3)
        #expect(CommandLauncher.index(0, movedBy: 1, count: 0) == 0)
    }

    // MARK: Files

    private func make(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func open(_ url: URL?) -> MarcdownFile {
        let file = MarcdownFile()
        file.fileURL = url
        return file
    }

    @Test func filesMergeOpenFilesAndPins() throws {
        let pins = Pins(defaults: UserDefaults(suiteName: suite)!, key: "pins")
        let store = OpenFiles(pins: pins)
        let a = open(try make("a.md")), b = open(try make("b.md")), untitled = open(nil)
        let closed = try make("closed.md")
        pins.pin(closed)
        pins.pin(b.url)
        [a, b, untitled].forEach(store.show)

        let items = PaletteItems.files(store)
        // Open files in sidebar order (pinned b first), then the closed pin; b shows once.
        #expect(items.map(\.title) == ["b", "a", "Untitled", "closed"])
        #expect(items.map(\.shortcut) == ["⌥⌘2", "", "", "⌥⌘1"])
        #expect(items.map(\.category) == ["Pin", "File", "File", "Pin"])
        #expect(items[0].id == PaletteItem.key(for: try #require(b.url)))
        #expect(items[3].id == PaletteItem.key(for: closed))
        #expect(items[2].id == "untitled:\(untitled.id.uuidString)")
        guard case .pin = items[0].action, case .file = items[1].action, case .pin = items[3].action else {
            Issue.record("wrong actions")
            return
        }
    }

    @Test func fileKeyIsTheResolvedPath() throws {
        let url = try make("c.md")
        let detour = url.deletingLastPathComponent().appending(path: "../\(folder.lastPathComponent)/c.md")
        #expect(PaletteItem.key(for: detour) == PaletteItem.key(for: url))
        #expect(PaletteItem.key(for: open(url)) == PaletteItem.key(for: url))
    }

    @Test func eachSwitchToAFileIsRecent() throws {
        let store = recency()
        let files = OpenFiles(pins: Pins(defaults: UserDefaults(suiteName: suite)!, key: "pins"), recency: store)
        let a = open(try make("a.md")), b = open(try make("b.md"))
        files.show(a)
        files.show(b)
        files.selectedID = a.id
        files.selectedID = nil
        #expect(store.keys == [PaletteItem.key(for: a), PaletteItem.key(for: b)])
    }
}
