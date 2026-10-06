import AppKit

/// Collects the palette rows from the live main menu and from the sidebar's files.
enum PaletteItems {
    /// The enabled commands of the menu bar in menu order: menus left to right, submenus in place.
    /// Standard macOS items are left out (see `MenuExclusion`), as are the pin items (the files list them).
    /// Refreshes the menus first (see `refresh`).
    @MainActor
    static func commands(in mainMenu: NSMenu) -> [PaletteItem] {
        refresh(mainMenu)
        var seen = Set<String>()
        return mainMenu.items.compactMap(\.submenu).flatMap(collect).filter { seen.insert($0.id).inserted }
    }

    /// SwiftUI sets `isEnabled`, toggled titles and changed items only when a menu is about to open, and
    /// `update()` alone does not ask it. So each submenu gets its delegate's `menuNeedsUpdate` first.
    /// Call it a run-loop turn after a state change at the earliest; it may replace items, so read after it.
    @MainActor
    static func refresh(_ menu: NSMenu) {
        for item in menu.items {
            guard let submenu = item.submenu, submenu !== NSApp.servicesMenu else { continue }
            submenu.delegate?.menuNeedsUpdate?(submenu)
            submenu.update()
            refresh(submenu)
        }
    }

    /// The live item at `path`, read after `refresh`. Among visible items with the title, the one with the
    /// path's shortcut wins, so a toggled title (Hide/Show Sidebar, see `PaletteItem.alias`) or a changed
    /// shortcut still finds it.
    @MainActor
    static func item(at path: MenuPath, in mainMenu: NSMenu) -> NSMenuItem? {
        var menu = mainMenu
        for title in path.titles.dropLast() {
            guard let submenu = menu.items.first(where: { $0.title == title && $0.submenu != nil })?.submenu else { return nil }
            menu = submenu
        }
        let title = PaletteItem.alias(path.titles.last ?? "")
        let named = menu.items.filter {
            !$0.isHidden && !$0.isAlternate && $0.submenu == nil && PaletteItem.alias($0.title) == title
        }
        return named.first {
            MenuPath(titles: path.titles, keyEquivalent: $0.keyEquivalent, modifiers: $0.keyEquivalentModifierMask) == path
        } ?? named.first
    }

    /// The recency key of an item that ran (`NSMenu.didSendActionNotification`), or nil when the launcher
    /// does not list it: the launcher itself, standard items, pins (their file counts when shown) and items
    /// in a left-out submenu (Open Recent, Services).
    @MainActor
    static func recencyKey(for item: NSMenuItem) -> String? {
        var current: NSMenuItem? = item
        while let checked = current {
            if MenuExclusion.excludes(checked) { return nil }
            current = checked.menu.flatMap(owner)
        }
        return PaletteItem.key(for: item)
    }

    /// The item that opens `menu` in its supermenu; nil for the menu bar.
    @MainActor
    static func owner(of menu: NSMenu) -> NSMenuItem? {
        menu.supermenu?.items.first { $0.submenu === menu }
    }

    /// One row per sidebar file, a pinned file once: the open files in sidebar order, then the closed pins.
    /// Pins carry their Window menu shortcut, ⌥⌘1 to ⌥⌘9 in pin order.
    @MainActor
    static func files(_ files: OpenFiles) -> [PaletteItem] {
        let rows = files.sidebarRows
        let number = Dictionary(uniqueKeysWithValues: files.pins.items.prefix(9).enumerated().map { ($1.id, $0 + 1) })
        let shortcut = { (pin: Pin?) in
            pin.flatMap { number[$0.id] }.map { PaletteItem.shortcut(key: "\($0)", modifiers: [.command, .option]) } ?? ""
        }
        let open = rows.all.compactMap { row -> PaletteItem? in
            guard let file = row.file else { return nil }
            return PaletteItem(id: PaletteItem.key(for: file),
                               category: row.pin == nil ? PaletteItem.fileCategory : PaletteItem.pinCategory,
                               title: file.title, shortcut: shortcut(row.pin), action: row.pin.map { .pin($0) } ?? .file(file))
        }
        let closed = rows.pinned.compactMap { row -> PaletteItem? in
            guard case .closedPin(let pin) = row else { return nil }
            return PaletteItem(id: PaletteItem.key(for: pin.url), category: PaletteItem.pinCategory, title: pin.name,
                               shortcut: shortcut(pin), action: .pin(pin))
        }
        return open + closed
    }

    @MainActor
    private static func collect(_ menu: NSMenu) -> [PaletteItem] {
        menu.items.flatMap { item -> [PaletteItem] in
            if item.isSeparatorItem || item.isHidden || item.isAlternate || MenuExclusion.excludes(item) { return [] }
            if let submenu = item.submenu { return collect(submenu) }
            // A disabled SwiftUI item also loses its action.
            guard item.isEnabled, item.action != nil, !item.title.isEmpty else { return [] }
            let path = MenuPath(item)
            return [PaletteItem(id: PaletteItem.key(for: path), category: PaletteItem.category(of: path.titles),
                                title: item.title, shortcut: PaletteItem.shortcut(of: item), action: .menu(path))]
        }
    }
}

/// The standard macOS menu items the palette leaves out: they belong to text fields, windows or the system,
/// and the user knows them by heart. Kept: Settings… and Enter/Exit Full Screen. The launcher's own item is out too.
/// Detection is by action selector and submenu identity first, by title second (for when AppKit changes them).
enum MenuExclusion {
    static let actions: Set<String> = [
        // App menu
        "orderFrontStandardAboutPanel:", "hide:", "hideOtherApplications:", "unhideAllApplications:", "terminate:",
        // Edit menu
        "undo:", "redo:", "cut:", "copy:", "paste:", "pasteAsPlainText:", "pasteAsRichText:", "delete:", "selectAll:",
        "startDictation:", "orderFrontCharacterPalette:", "showWritingTools:",
        "showGuessPanel:", "checkSpelling:", "toggleContinuousSpellChecking:", "toggleGrammarChecking:",
        "toggleAutomaticSpellingCorrection:", "orderFrontSubstitutionsPanel:", "toggleSmartInsertDelete:",
        "toggleAutomaticQuoteSubstitution:", "toggleAutomaticDashSubstitution:", "toggleAutomaticLinkDetection:",
        "toggleAutomaticDataDetection:", "toggleAutomaticTextReplacement:",
        "uppercaseWord:", "lowercaseWord:", "capitalizeWord:", "startSpeaking:", "stopSpeaking:",
        // Window menu
        "performMiniaturize:", "performZoom:", "miniaturizeAll:", "zoomAll:", "arrangeInFront:", "makeKeyAndOrderFront:",
        "toggleTabBar:", "toggleTabOverview:", "selectNextTab:", "selectPreviousTab:", "mergeAllWindows:",
        "moveTabToNewWindow:",
        // File > Open Recent, Help
        "clearRecentDocuments:", "showHelp:",
    ]

    /// Submenus and items by title. App-named items ("Hide Marc") are covered by their selectors only.
    static let titles: Set<String> = [
        "Services", "Hide Others", "Show All",
        "Open Recent",
        "Undo", "Redo", "Cut", "Copy", "Paste", "Paste and Match Style", "Delete", "Select All",
        "AutoFill", "Start Dictation", "Start Dictation…", "Emoji & Symbols", "Writing Tools",
        "Spelling and Grammar", "Substitutions", "Transformations", "Speech",
        "Minimize", "Minimize All", "Zoom", "Zoom All", "Fill", "Center", "Move & Resize", "Full Screen Tile",
        "Remove Window from Set", "Bring All to Front",
        CommandLauncher.menuTitle,
    ]

    @MainActor
    static func excludes(_ item: NSMenuItem) -> Bool {
        if let submenu = item.submenu, submenu === NSApp.servicesMenu { return true }
        if item.target is NSWindow || item.view != nil { return true }   // window list; Help menu search
        if let action = item.action.map(NSStringFromSelector),
           actions.contains(action) || action.hasPrefix("_") {           // private: AutoFill, window tiling
            return true
        }
        return titles.contains(item.title) || isPinItem(item)
    }

    /// Window > a pinned file (⌥⌘1 to ⌥⌘9); the palette lists it among the files.
    private static func isPinItem(_ item: NSMenuItem) -> Bool {
        item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.command, .option]
            && item.keyEquivalent.count == 1 && ("1"..."9").contains(item.keyEquivalent)
    }
}
