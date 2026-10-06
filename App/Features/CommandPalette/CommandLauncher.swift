import AppKit

/// The launcher's state (⇧⌘P): open or not, the query, the ranked rows and the selected one. `LauncherOverlay`
/// shows it over the main window. The rows are read once per open, before the search field takes the focus,
/// so items that go to the first responder (Show Sidebar) are validated against the editor.
@MainActor
@Observable
final class CommandLauncher {
    static let shared = CommandLauncher()
    /// View > Command Launcher…; the launcher does not list it, and it does not count as recent.
    nonisolated static let menuTitle = "Command Launcher…"

    private(set) var isOpen = false
    /// Typing ranks again and selects the first row.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rank()
            selection = 0
        }
    }
    private(set) var rows: [PaletteItem] = []
    private(set) var selection = 0
    /// Goes up with a ⇧⌘P while open; the panel then focuses its search field again (on open, `onAppear` does).
    private(set) var focusRequest = 0

    @ObservationIgnored private var files: [PaletteItem] = []
    @ObservationIgnored private var commands: [PaletteItem] = []

    private init() {
        // Closes when the main window is no longer key, and on a click in its title bar or toolbar (the
        // overlay covers only the content; a click there closes it in `LauncherOverlay`).
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: nil) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if window === OpenFiles.shared.window { self.close() }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if self.isOpen, let window = event.window, window === OpenFiles.shared.window,
               !window.contentLayoutRect.contains(event.locationInWindow) {
                self.close()
            }
            return event
        }
    }

    /// Show the main window (also when all files were closed) with the launcher. Again while open: keep it
    /// and focus the search field.
    func open() {
        let wasKey = OpenFiles.shared.window?.isKeyWindow == true
        OpenFiles.shared.showWindow()
        guard !isOpen else { focusRequest += 1; return }
        // A window that just became key changes the menus; they can be read a turn later (see `PaletteItems.refresh`).
        if wasKey { present() } else { DispatchQueue.main.async { self.present() } }
    }

    private func present() {
        guard !isOpen else { return }
        commands = NSApp.mainMenu.map(PaletteItems.commands) ?? []
        files = PaletteItems.files(.shared)
        query = ""
        rank()
        selection = 0
        isOpen = true
    }

    /// Esc, a click outside, the window resigning key, or before a row runs. The editor gets the keys back.
    func close() {
        guard isOpen else { return }
        isOpen = false
        focusEditor()
    }

    /// ↑ and ↓; they wrap at the ends.
    func move(by offset: Int) {
        selection = Self.index(selection, movedBy: offset, count: rows.count)
    }

    /// Mouse hover.
    func select(_ index: Int) {
        if rows.indices.contains(index) { selection = index }
    }

    /// Return.
    func runSelection() {
        if rows.indices.contains(selection) { run(rows[selection]) }
    }

    /// The single place a row runs. A menu command runs a turn after the launcher closed and the editor took
    /// the focus, so responder-chain items reach the editor, not the search field. Its item is looked up again
    /// then (SwiftUI replaces items), and it runs through its menu, which posts `didSendActionNotification`
    /// like a click, so `CommandRecency` counts it there.
    func run(_ item: PaletteItem) {
        close()
        switch item.action {
        case .menu(let path):
            DispatchQueue.main.async {
                guard let mainMenu = NSApp.mainMenu else { return }
                PaletteItems.refresh(mainMenu)
                guard let found = PaletteItems.item(at: path, in: mainMenu), found.isEnabled, found.action != nil,
                      let menu = found.menu
                else { return NSSound.beep() }
                menu.performActionForItem(at: menu.index(of: found))
            }
        case .file(let file):
            CommandRecency.shared.record(item.id)   // also when it is shown already (no selection change)
            OpenFiles.shared.selectedID = file.id
        case .pin(let pin):
            CommandRecency.shared.record(item.id)
            OpenFiles.shared.activate(pin)
        }
    }

    /// `index` moved by `offset`, wrapping around `count` rows; 0 when there are none.
    nonisolated static func index(_ index: Int, movedBy offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + offset) % count + count) % count
    }

    private func rank() {
        rows = PaletteRanking.rank(files: files, commands: commands, query: query, recency: CommandRecency.shared.keys)
    }

    private func focusEditor() {
        let files = OpenFiles.shared
        guard files.selected != nil, let editor = files.editor, !editor.editorIsHidden else { return }
        editor.focusTextView()
    }
}
