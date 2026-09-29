import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown → a standalone HTML page for Print and Export as PDF.
/// cmark-gfm renders the HTML (swift-markdown's HTMLFormatter does not escape text or code).
enum PrintRenderer {
    /// A full HTML page. Front matter is dropped. `baseFolder` (the document folder) resolves
    /// relative image and link paths. `fontFamily` is a family name, or nil for the system font.
    static func page(markdown: String, title: String, baseFolder: URL?, fontFamily: String?) -> String {
        let base = baseFolder.map { "<base href=\"\(escape($0.absoluteString))\">\n" } ?? ""
        let font = fontFamily.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\", " } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(base)<title>\(escape(title))</title>
        <style>
        :root { font-family: \(font)-apple-system, sans-serif; }
        \(stylesheet)
        </style>
        </head>
        <body>
        \(body(markdown: FrontMatterSplit.split(markdown).body))</body>
        </html>
        """
    }

    /// GFM → HTML fragment: tables, ~~strikethrough~~, task lists, autolinks. Raw HTML is kept.
    static func body(markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        // Double tilde only: the editor shows `~text~` as plain text.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Always light, whatever the system appearance. Page margins come from NSPrintInfo.
    private static let stylesheet = """
    html { color: #1d1d1f; background: white; font-size: 11pt; line-height: 1.5;
           -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    body { margin: 0; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.5em; break-after: avoid; }
    h1 { font-size: 1.8em; } h2 { font-size: 1.45em; } h3 { font-size: 1.2em; }
    h4, h5, h6 { font-size: 1em; }
    body > :first-child { margin-top: 0; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 0.8em; }
    ul, ol { padding-left: 1.6em; }
    li > p { margin: 0; }
    li:has(> input[type=checkbox]) { list-style: none; }
    li > input[type=checkbox] { margin: 0 0.4em 0 -1.4em; }
    a { color: #0060c0; text-decoration: none; }
    code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
    code { background: #f2f2f4; border-radius: 3px; padding: 0.05em 0.3em; }
    pre { background: #f2f2f4; border-radius: 5px; padding: 0.7em 0.9em;
          white-space: pre-wrap; overflow-wrap: anywhere; break-inside: avoid; }
    pre code { background: none; padding: 0; font-size: 1em; }
    blockquote { color: #555; border-left: 3px solid #d0d0d5; padding-left: 0.9em; margin-left: 0; }
    hr { border: none; border-top: 1px solid #d0d0d5; margin: 1.4em 0; }
    img { max-width: 100%; break-inside: avoid; }
    table { border-collapse: collapse; break-inside: avoid; }
    th, td { border: 1px solid #d0d0d5; padding: 0.3em 0.6em; }
    th { background: #f2f2f4; }
    del { color: #777; }
    """
}
