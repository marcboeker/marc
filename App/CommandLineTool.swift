import AppKit
import SwiftUI

/// "Install Command Line Tool…": symlinks the bundled `marcdown` script into ~/.local/bin.
struct CommandLineToolCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Install Command Line Tool…") { CommandLineTool.install() }
        }
    }
}

@MainActor
enum CommandLineTool {
    static func install() {
        let alert = NSAlert()
        do {
            let link = try createLink()
            alert.messageText = "Command line tool installed"
            alert.informativeText = "\(link.path) now points to Marcdown. Make sure \(link.deletingLastPathComponent().path) is in your PATH, then run: marcdown notes.md"
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Could not install the command line tool"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }

    private static func createLink() throws -> URL {
        guard let script = Bundle.main.url(forResource: "marcdown", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The marcdown script is missing from the app bundle."])
        }
        let fm = FileManager.default
        let bin = fm.homeDirectoryForCurrentUser.appending(path: ".local/bin", directoryHint: .isDirectory)
        let link = bin.appending(path: "marcdown")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        // Replace an old symlink, but never a real file.
        if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if existing == script.path { return link }
            try fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "\(link.path) exists and is not a symlink."])
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: script)
        return link
    }
}
