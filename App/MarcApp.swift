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
        DocumentGroup(newDocument: MarcDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            SidebarCommands()           // View > Show/Hide Sidebar, ⌃⌘S
            FontSizeCommands()          // Features/Appearance
            FindCommands()              // Features/Find
            FormatCommands()            // Features/Shortcuts
            PrintCommands()             // Features/Print
            CommandLineToolCommands()   // App/CommandLineTool.swift
        }
        Settings {
            AppearanceSettingsView()    // Features/Appearance
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FontSizeCommands.installEqualsShortcut()
    }

    /// `marc://clip?…` from the `marc` script (see WebClip).
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(WebClip.open)
    }
}
