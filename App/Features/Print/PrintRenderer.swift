import Foundation

/// Markdown → a standalone HTML page for Print and Export as PDF. The HTML comes from MarkdownHTML.
enum PrintRenderer {
    /// A full HTML page. Front matter is dropped. `baseFolder` (the document folder) resolves
    /// relative image and link paths. `fontFamily` is a family name, or nil for the system font.
    static func page(markdown: String, title: String, baseFolder: URL?, fontFamily: String?) -> String {
        let base = baseFolder.map { "<base href=\"\(MarkdownHTML.escape($0.absoluteString))\">\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(base)<title>\(MarkdownHTML.escape(title))</title>
        <style>
        :root { font-family: \(MarkdownHTML.fontFamily(fontFamily)); }
        \(stylesheet)
        </style>
        </head>
        <body>
        \(body(markdown: FrontMatterSplit.split(markdown).body))</body>
        </html>
        """
    }

    /// GFM → HTML fragment, without source positions (see MarkdownHTML).
    static func body(markdown: String) -> String {
        MarkdownHTML.render(markdown)
    }

    /// Always light, whatever the system appearance. Page margins come from NSPrintInfo.
    /// The shared rules come from MarkdownHTML; `pre` wraps and blocks do not break across pages.
    private static let stylesheet = """
    html { color: #1d1d1f; background: white; font-size: 11pt; line-height: 1.5;
           -webkit-print-color-adjust: exact; print-color-adjust: exact;
           --link: #0060c0; --rule: #d0d0d5; --fill: #f2f2f4; --secondary: #777; }
    body { margin: 0; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.5em; break-after: avoid; }
    body > :first-child { margin-top: 0; }
    \(MarkdownHTML.stylesheet)
    code { background: var(--fill); border-radius: 3px; padding: 0.05em 0.3em; }
    pre { background: var(--fill); border-radius: 5px; padding: 0.7em 0.9em;
          white-space: pre-wrap; overflow-wrap: anywhere; }
    blockquote { color: #555; border-left: 3px solid var(--rule); padding-left: 0.9em; margin-left: 0; }
    pre, img, table { break-inside: avoid; }
    """
}
