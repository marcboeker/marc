import AppKit

/// One palette row: a main menu command or a file from the sidebar. `id` is the recency key, stable across
/// launches and title toggles, so `CommandRecency` can store it. `CommandLauncher.run` runs it.
struct PaletteItem: Identifiable {
    enum Action {
        /// By value: SwiftUI replaces its menu items when state changes, so the item is looked up again to run.
        case menu(MenuPath)
        /// An open file that is not pinned.
        case file(MarcdownFile)
        /// A pinned file, open or closed.
        case pin(Pin)
    }

    let id: String
    /// The dimmed prefix, "Format" for Bold, "File" for an open file (see `category(of:)`).
    let category: String
    let title: String
    /// "⌃⌘P"; "" when none.
    let shortcut: String
    let action: Action

    static let fileCategory = "File", pinCategory = "Pin"
}

/// Where a menu command is: the titles from the menu bar down, and its shortcut to tell items with the
/// same title apart. `PaletteItems.item(at:in:)` finds the live item.
struct MenuPath: Hashable {
    let titles: [String]
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags.RawValue

    init(titles: [String], keyEquivalent: String = "", modifiers: NSEvent.ModifierFlags = []) {
        self.titles = titles
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    @MainActor
    init(_ item: NSMenuItem) {
        var titles = [item.title]
        var menu = item.menu
        while let current = menu, let owner = PaletteItems.owner(of: current) {
            titles.insert(owner.title, at: 0)
            menu = current.supermenu
        }
        self.init(titles: titles, keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }
}

// MARK: Recency keys

extension PaletteItem {
    /// Titles that toggle with state share the key of their first form, so "Unpin File" is recent after "Pin File".
    static let titleAliases = [
        FileCommands.unpinTitle: FileCommands.pinTitle,
        "Hide Sidebar": "Show Sidebar",
        "Exit Full Screen": "Enter Full Screen",
        "Hide Toolbar": "Show Toolbar",
    ]

    static func alias(_ title: String) -> String { titleAliases[title] ?? title }

    /// The menu path, e.g. "View/Preview" or "Edit/Find/Find…". Also for an item from
    /// `NSMenu.didSendActionNotification` (userInfo "MenuItem").
    @MainActor
    static func key(for item: NSMenuItem) -> String {
        key(for: MenuPath(item))
    }

    static func key(for path: MenuPath) -> String {
        (path.titles.dropLast() + [alias(path.titles.last ?? "")]).joined(separator: "/")
    }

    /// The pin key's path, the same for a pin and its open file.
    @MainActor
    static func key(for url: URL) -> String {
        Pins.key(url).path(percentEncoded: false)
    }

    /// The file's path; an untitled file has only its id, which does not outlive the file.
    @MainActor
    static func key(for file: MarcdownFile) -> String {
        file.url.map { key(for: $0) } ?? "untitled:\(file.id.uuidString)"
    }
}

// MARK: Categories

extension PaletteItem {
    /// Items whose menu name is too broad. Toggled titles go through `alias` first.
    static let categoriesByTitle = [
        "Page Setup…": "Print", "Export as PDF…": "Print", "Print…": "Print",
        "Bigger": "Text Size", "Smaller": "Text Size", "Default Size": "Text Size",
        "Settings…": "App", "Install Command Line Tool…": "App",
    ]

    /// Menus whose name says too little. "File" is the open files' prefix, so the File menu is "Document".
    static let categoriesByMenu = ["File": "Document", "Window": "Go"]

    /// The prefix of a menu command at `titles` (see `MenuPath`): by title, else an Edit submenu's name
    /// (Find), else by menu, else the menu's own name, so a new command gets a sensible prefix by itself.
    static func category(of titles: [String]) -> String {
        guard let menu = titles.first, titles.count > 1 else { return "" }
        if let category = categoriesByTitle[alias(titles[titles.count - 1])] { return category }
        if menu == "Edit", titles.count > 2 { return titles[1] }
        return categoriesByMenu[menu] ?? menu
    }
}

// MARK: Shortcut display

extension PaletteItem {
    /// The shortcut as the menu shows it, modifiers in macOS order fn ⌃⌥⇧⌘. An uppercase letter implies ⇧.
    /// fn only with a plain key (Enter Full Screen): arrows and F-keys carry the flag by themselves.
    static func shortcut(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        guard !key.isEmpty else { return "" }
        var modifiers = modifiers
        if key.count == 1, key != key.lowercased() { modifiers.insert(.shift) }
        if let scalar = key.unicodeScalars.first, (0xF700...0xF8FF).contains(scalar.value) { modifiers.remove(.function) }
        return modifierSymbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName(key)
    }

    private static let modifierSymbols: [(NSEvent.ModifierFlags, String)] = [
        (.function, "fn "), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    private static let keyNames: [Int: String] = [
        0x0D: "↩", 0x03: "⌤", 0x09: "⇥", 0x1B: "⎋", 0x20: "Space", 0x08: "⌫", 0x7F: "⌫",
        NSDeleteFunctionKey: "⌦", NSUpArrowFunctionKey: "↑", NSDownArrowFunctionKey: "↓",
        NSLeftArrowFunctionKey: "←", NSRightArrowFunctionKey: "→", NSHomeFunctionKey: "↖", NSEndFunctionKey: "↘",
        NSPageUpFunctionKey: "⇞", NSPageDownFunctionKey: "⇟",
    ]

    @MainActor
    static func shortcut(of item: NSMenuItem) -> String {
        shortcut(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

    private static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return key.uppercased() }
        let code = Int(scalar.value)
        if let name = keyNames[code] { return name }
        if (NSF1FunctionKey...NSF35FunctionKey).contains(code) { return "F\(code - NSF1FunctionKey + 1)" }
        return key.uppercased()
    }
}
