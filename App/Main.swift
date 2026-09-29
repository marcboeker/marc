import AppKit

/// `Marc --clip <url>` runs headless for the `marc` script (see WebClip); anything else starts the app.
@main
enum Main {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count > 1, arguments[1] == "--clip" else {
            MarcApp.main()
            return
        }
        // WebKit needs a running app event loop; `.prohibited` keeps it out of the Dock.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            exit(await WebClip.run(arguments: Array(arguments.dropFirst(2))))
        }
        app.run()
    }
}
