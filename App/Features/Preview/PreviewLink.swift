import Foundation

/// What a click on a link in the preview does. The web view itself never leaves the preview page.
enum PreviewLink: Equatable {
    /// `#name` in this document: scroll the preview.
    case anchor(String)
    /// A Markdown file: open it in Marcdown.
    case markdownFile(URL)
    /// Any other local file or folder: show it in Finder. Never open it: it could be an app or a script.
    case localFile(URL)
    /// A web page or mail address: the default app opens it.
    case web(URL)
    /// Nothing to do: another URL scheme, or a relative link in an unsaved document.
    case ignored

    /// Schemes that go to `NSWorkspace.open`. Other schemes could start any app, so they are ignored.
    static let webSchemes: Set<String> = ["http", "https", "mailto"]

    /// `url` is resolved against `<base href>` (`PreviewScheme.base(baseFolder)`), or against
    /// `PreviewScheme.pageURL` without a base, so `#name` comes in as the folder or page URL with a fragment.
    static func classify(_ url: URL, baseFolder: URL?) -> PreviewLink {
        let fragment = url.fragment(percentEncoded: false).flatMap { $0.isEmpty ? nil : $0 }
        if url.scheme == PreviewScheme.name, url.host() == "page" {
            // Only the unsaved document has no base: `#name` works, other relative links have no folder.
            let isPage = url.path(percentEncoded: false).isEmpty || url.path(percentEncoded: false) == "/"
            guard isPage, let fragment else { return .ignored }
            return .anchor(fragment)
        }
        let file = url.isFileURL ? url : PreviewScheme.fileURL(url)
        if let file {
            if let fragment, let baseFolder, sameFile(file, baseFolder) { return .anchor(fragment) }
            var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            components?.query = nil
            let plain = components?.url ?? file
            return plain.isMarkdownFile ? .markdownFile(plain) : .localFile(plain)
        }
        if let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) { return .web(url) }
        return .ignored
    }

    /// Same file path after `..` and symlinks, without fragment, query or a trailing slash.
    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        func path(_ url: URL) -> String {
            let path = url.resolvedFileURL.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return path(a) == path(b)
    }
}
