import AppKit
import SwiftUI
import MarkdownEngine

/// Started from Main.swift.
struct MarcApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        // Plain GFM only: no wiki links, ![[embeds]], LaTeX. Must run before any editor exists.
        MarkdownEngineFeatures.disableNonGFM()
    }

    var body: some Scene {
        // One window for all files (OpenFiles). Closing it only hides it; see MainWindow.swift.
        Window("Marc", id: "main") {
            ContentView()
        }
        .commands {
            FileCommands()              // App/FileCommands.swift
            SidebarCommands()           // View > Show/Hide Sidebar, ⌃⌘S
            PreviewCommands()           // Features/Preview: View > Preview ⌃⌘P, Side by Side ⌥⌘P
            FontSizeCommands()          // Features/Appearance
            FindCommands()              // Features/Find
            FormatCommands()            // Features/Shortcuts
            PrintCommands()             // Features/Print
            CommandLineToolCommands()   // App/CommandLineTool.swift
            LauncherCommands()          // Features/CommandPalette: View > Command Launcher… ⇧⌘P
        }
        Settings {
            AppearanceSettingsView()    // Features/Appearance
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // One window for all files: no tabs, and no Show Tab Bar / Show All Tabs in the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontSizeCommands.installEqualsShortcut()
        CommandRecency.shared.observeMenus()
    }

    /// Files from Finder, the Dock and `open -a Marc`; `marc://clip?…` from the `marc` script (see WebClip).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL { OpenFiles.shared.open(url) } else { WebClip.open(url) }
        }
    }

    /// Launch shows the empty window, not a new untitled file.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// A single `Window` scene would quit the app when its window closes; Marc stays, like a document app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The Dock icon brings back the main window after it was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { OpenFiles.shared.showWindow() }
        return false
    }
}
