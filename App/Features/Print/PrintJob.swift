import AppKit
import WebKit

/// Loads a printable HTML page into an off-screen web view, then prints it or saves it as a PDF.
/// A job keeps itself alive until the print operation ends.
@MainActor
final class PrintJob: NSObject, WKNavigationDelegate {
    enum Output {
        /// Show the print panel. Its PDF menu also saves PDFs.
        case printPanel
        /// Write a paginated PDF to this URL without a panel.
        case pdf(URL)
    }

    private static var running: Set<PrintJob> = []

    private let title: String
    private let output: Output
    private weak var window: NSWindow?
    private let folder: URL
    private let webView: WKWebView

    static func start(html: String, title: String, output: Output, window: NSWindow?) {
        let job = PrintJob(title: title, output: output, window: window)
        running.insert(job)
        job.load(html)
    }

    private init(title: String, output: Output, window: NSWindow?) {
        self.title = title
        self.output = output
        self.window = window
        folder = FileManager.default.temporaryDirectory.appending(path: "Marcdown-Print-\(UUID().uuidString)", directoryHint: .isDirectory)
        let configuration = WKWebViewConfiguration()
        // The page is the user's own Markdown, but raw HTML in it must not run scripts.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 800), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// Through a file, not `loadHTMLString`: only file loads may read local images from any folder.
    private func load(_ html: String) {
        let page = folder.appending(path: "page.html")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: page)
        } catch {
            fail(error)
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: URL(filePath: "/"))
    }

    /// Called after the load event, so images are in.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (54, 54, 54, 54)
        if case .pdf(let url) = output {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }

        let operation = webView.printOperation(with: info)
        operation.jobTitle = title
        if case .pdf = output { operation.showsPrintPanel = false }
        // Without a frame on the print view, WebKit prints blank pages.
        operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        if let window {
            // `run()` also gives blank pages for a WKWebView; the modal variant works.
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            operation.run()
            finish()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish()
    }

    private func fail(_ error: Error) {
        if let window { window.presentError(error) } else { NSApp.presentError(error) }
        finish()
    }

    private func finish() {
        webView.navigationDelegate = nil
        try? FileManager.default.removeItem(at: folder)
        Self.running.remove(self)
    }
}
