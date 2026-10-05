import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown → HTML fragment, shared by Print and Preview.
/// cmark-gfm renders the HTML (swift-markdown's HTMLFormatter does not escape text or code).
enum MarkdownHTML {
    /// GFM → HTML fragment: tables, ~~strikethrough~~, task lists, autolinks. Raw HTML is kept.
    /// With `sourcePositions` the elements carry `data-sourcepos="line:col-line:col"` (lines of `markdown`).
    static func render(_ markdown: String, sourcePositions: Bool = false) -> String {
        parse(markdown, sourcePositions: sourcePositions) { document, render in render(document) } ?? ""
    }

    /// Parse `markdown` and pass its document node to `body`, with a function that renders a node to HTML.
    /// The nodes live only during `body`. Nil when cmark fails.
    static func parse<T>(_ markdown: String, sourcePositions: Bool,
                         _ body: (_ document: UnsafeMutablePointer<cmark_node>,
                                  _ render: (UnsafeMutablePointer<cmark_node>) -> String) -> T) -> T? {
        cmark_gfm_core_extensions_ensure_registered()
        // Double tilde only: the editor shows `~text~` as plain text.
        var options = CMARK_OPT_UNSAFE | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE
        if sourcePositions { options |= CMARK_OPT_SOURCEPOS }
        guard let parser = cmark_parser_new(options) else { return nil }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return nil }
        defer { cmark_node_free(document) }
        let extensions = cmark_parser_get_syntax_extensions(parser)
        return body(document) { node in
            guard let html = cmark_render_html(node, options, extensions) else { return "" }
            defer { free(html) }
            return String(cString: html)
        }
    }

    /// Text for HTML content and attribute values.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// CSS `font-family` value: `family` (a family name, or nil for the system font), then the system font.
    static func fontFamily(_ family: String?) -> String {
        let named = family.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\", " } ?? ""
        return "\(named)-apple-system, sans-serif"
    }

    /// The rules Print and Preview share. Each page sets the colours `--link`, `--rule`, `--fill` and
    /// `--secondary`, and adds its own line heights, heading margins, code, pre and blockquote looks.
    static let stylesheet = """
    h1 { font-size: 1.8em; } h2 { font-size: 1.45em; } h3 { font-size: 1.2em; }
    h4, h5, h6 { font-size: 1em; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 0.8em; }
    ul, ol { padding-left: 1.6em; }
    li > p { margin: 0; }
    li:has(> input[type=checkbox]) { list-style: none; }
    li > input[type=checkbox] { margin: 0 0.4em 0 -1.4em; }
    a { color: var(--link); text-decoration: none; }
    code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
    pre code { background: none; padding: 0; font-size: 1em; }
    hr { border: none; border-top: 1px solid var(--rule); margin: 1.4em 0; }
    img { max-width: 100%; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid var(--rule); padding: 0.3em 0.6em; }
    th { background: var(--fill); }
    del { color: var(--secondary); }
    """
}
