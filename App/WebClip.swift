import AppKit
import Demark
import Foundation
import Markdown
import UniformTypeIdentifiers

/// `marc <url>`: loads a web page, converts it to Markdown with Demark, opens it as a new untitled document.
/// The `marc` script runs `Marc --clip <url>` headless, which writes the Markdown to a temporary file
/// and prints a `marc://clip?file=<path>` URL; the script opens that URL in the app (see `open(_:)`).
@MainActor
enum WebClip {
    /// Returns the exit status. On success, prints the `marc://clip` URL to stdout.
    static func run(arguments: [String]) async -> Int32 {
        guard arguments.count == 1,
              let url = URL(string: arguments[0]),
              ["http", "https"].contains(url.scheme?.lowercased())
        else {
            printError("usage: Marc --clip <http(s) url>")
            return 64
        }
        do {
            let markdown = try await convert(url)
            let file = try writeTemporary(markdown, name: WebClipMarkdown.fileName(markdown: markdown, url: url))
            var clip = URLComponents()
            clip.scheme = "marc"
            clip.host = "clip"
            clip.queryItems = [URLQueryItem(name: "file", value: file.path)]
            print(clip.url!.absoluteString)
            return 0
        } catch {
            printError("marc: \(url.absoluteString): \(error.localizedDescription)")
            return 1
        }
    }

    /// Handles `marc://clip?file=<path>` in the app: a new untitled document with the file's text,
    /// named like the file, so Save proposes `<slug>.md`. Deletes the temporary folder. Ignores other URLs.
    static func open(_ url: URL) {
        guard url.scheme == "marc", url.host() == "clip",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "file" })?.value
        else { return }
        let file = URL(filePath: path)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let controller = NSDocumentController.shared
        do {
            // Not duplicateDocument: it names the window "<name> copy".
            let document = try controller.makeDocument(for: nil, withContentsOf: file, ofType: UTType.markdown.identifier)
            document.displayName = file.deletingPathExtension().lastPathComponent
            controller.addDocument(document)
            document.showWindows()   // MarcFile: adds it to OpenFiles and selects it
        } catch {
            NSApp.presentError(error)
        }
    }

    /// The page's main content if it marks one, else the whole page, without menus and footers.
    private static func convert(_ url: URL) async throws -> String {
        let demark = Demark()
        let options = DemarkOptions(ignoreTags: ["nav", "footer", "form", "noscript"])
        var markdown: String
        do {
            let main = URLLoadingOptions(contentSelector: "main, [role=main], article")
            markdown = try await demark.convertToMarkdown(url: url, options: options, loadingOptions: main)
        } catch DemarkError.contentSelectorNotFound {
            markdown = try await demark.convertToMarkdown(url: url, options: options)
        }
        markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else { throw DemarkError.emptyResult }
        return WebClipMarkdown.finish(markdown, base: url)
    }

    /// `<name>.md` in a new temporary folder, which `open(_:)` deletes after reading.
    private static func writeTemporary(_ markdown: String, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "marc-clip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(name).md")
        try Data(markdown.utf8).write(to: file)
        return file
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// Pure parts of the clip, tested in Tests/WebClipTests.swift.
enum WebClipMarkdown {
    /// Link and image targets made absolute against the page URL (a local file cannot follow `/blog/`),
    /// empty links (logos, heading anchors) removed, then formatted like ⌘S.
    static func finish(_ markdown: String, base: URL) -> String {
        var resolver = LinkResolver(base: base)
        // No smart punctuation: `--flag`, "quotes" and `...` must stay as the page has them.
        let document = resolver.visit(Document(parsing: markdown, options: .disableSmartOpts))!
        // `document.format()` prints every strikethrough with one `~`; the page meant all of them.
        return MarkdownFormatting.format(document.format(), doublingSingleTildes: true)
    }

    /// Slug (without `.md`) of the first H1, else the URL's last path part, else the host.
    static func fileName(markdown: String, url: URL) -> String {
        let headings = outline(of: markdown).filter { $0.level == 1 }.map(\.title)
        // Not deletingPathExtension: "swift-6.4-released" has no extension.
        let page = url.lastPathComponent.replacing(/(?i)\.(html?|php|aspx?|jsp)$/, with: "")
        let candidates = headings + [page, url.host() ?? ""]
        return candidates.lazy.map(slug).first { !$0.isEmpty } ?? "page"
    }

    /// Lowercase words joined by `-`, cut at a word boundary after at most 60 characters.
    static func slug(_ text: String) -> String {
        var result = ""
        for word in text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let next = result.isEmpty ? String(word) : result + "-" + word
            if next.count > 60 { return result.isEmpty ? String(next.prefix(60)) : result }
            result = next
        }
        return result
    }
}

private struct LinkResolver: MarkupRewriter {
    let base: URL

    mutating func visitHeading(_ heading: Heading) -> Markup? {
        let heading = defaultVisit(heading) as! Heading
        return heading.plainText.allSatisfy(\.isWhitespace) ? nil : heading
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        guard link.childCount > 0 else { return nil }
        var link = link
        link.destination = resolve(link.destination)
        return defaultVisit(link)
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        var image = image
        image.source = resolve(image.source)
        return defaultVisit(image)
    }

    private func resolve(_ target: String?) -> String? {
        guard let target, !target.isEmpty else { return target }
        return URL(string: target, relativeTo: base)?.absoluteString ?? target
    }
}
