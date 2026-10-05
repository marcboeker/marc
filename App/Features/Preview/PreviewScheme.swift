import Foundation
import UniformTypeIdentifiers
import WebKit

/// The preview's own URL scheme. The page comes from `marc-preview://page/`, files from
/// `marc-preview://file/<absolute path>`. The web view gets no file read access at all: Marc reads
/// the files and gives out only those in the document folder and its subfolders.
enum PreviewScheme {
    static let name = "marc-preview"
    static let pageURL = URL(string: "\(name)://page/")!

    /// `<base href>` for the document folder: relative images and links resolve inside the scheme.
    static func base(_ folder: URL?) -> String {
        guard let folder else { return "" }
        let path = folder.path(percentEncoded: true)
        return "\(name)://file\(path.hasSuffix("/") ? path : path + "/")"
    }

    /// The file a `marc-preview://file/…` URL stands for, without query and fragment. Nil for other URLs.
    static func fileURL(_ url: URL) -> URL? {
        guard url.scheme == name, url.host() == "file" else { return nil }
        let path = url.path(percentEncoded: false)
        return URL(filePath: path.isEmpty ? "/" : path, directoryHint: path.hasSuffix("/") ? .isDirectory : .inferFromPath)
    }

    /// `file` when it is in `folder` or below it (after symlinks and `..`), otherwise nil.
    static func allowed(_ file: URL, in folder: URL?) -> URL? {
        root(folder).flatMap { allowed(file, root: $0) }
    }

    /// The path prefix that `allowed(_:root:)` checks: the folder after symlinks, with a trailing slash.
    static func root(_ folder: URL?) -> String? {
        guard let folder else { return nil }
        let root = folder.resolvedFileURL.path(percentEncoded: false)
        return root.hasSuffix("/") ? root : root + "/"
    }

    /// `file` when it is below `root` (from `root(_:)`) after symlinks and `..`, otherwise nil.
    static func allowed(_ file: URL, root: String) -> URL? {
        let resolved = file.resolvedFileURL
        return resolved.path(percentEncoded: false).hasPrefix(root) ? resolved : nil
    }

    /// Contents and MIME type of `file` when it is below `root`. Reads from disk, so not on the main thread.
    static func read(_ file: URL, root: String) -> (data: Data, mimeType: String)? {
        guard !Task.isCancelled, let file = allowed(file, root: root),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return (data, UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
    }
}

/// Answers the web view's `marc-preview:` loads: the page, and files in the document folder.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    /// HTML of the page; set before each page load.
    var page = ""
    /// The folder files may come from; nil gives out no files.
    var folder: () -> URL? = { nil }

    /// File loads that run now, by scheme task. `stop` removes a task, so it is not answered after that.
    private var loads: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// The last folder and its `PreviewScheme.root`, so symlinks resolve once per folder, not per file.
    private var cachedRoot: (folder: URL, root: String)?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        if url.host() == "page" {
            return Self.answer(task, url: url, data: Data(page.utf8), mimeType: "text/html")
        }
        guard let file = PreviewScheme.fileURL(url), let root = root() else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        // The check and the read go off the main thread; the answer comes back on it.
        let id = ObjectIdentifier(task)
        let read = Task.detached(priority: .userInitiated) { PreviewScheme.read(file, root: root) }
        loads[id] = Task { [weak self] in
            let result = await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
            // Stopped: WebKit raises an exception when a stopped task gets an answer.
            guard let self, self.loads.removeValue(forKey: id) != nil else { return }
            // The page switched to another folder during the read: its files only.
            guard let result, self.root() == root else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
            Self.answer(task, url: url, data: result.data, mimeType: result.mimeType)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        loads.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }

    /// `PreviewScheme.root` of the folder the page shows now; resolved again only when the folder changes.
    private func root() -> String? {
        guard let folder = folder() else { return nil }
        if let cachedRoot, cachedRoot.folder == folder { return cachedRoot.root }
        guard let root = PreviewScheme.root(folder) else { return nil }
        cachedRoot = (folder, root)
        return root
    }

    private static func answer(_ task: any WKURLSchemeTask, url: URL, data: Data, mimeType: String) {
        task.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count,
                                    textEncodingName: mimeType == "text/html" ? "utf-8" : nil))
        task.didReceive(data)
        task.didFinish()
    }
}
