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
        \(stylesheet(fontFamily: fontFamily))
        </style>
        </head>
        <body>
        <main>\(MarkdownHTML.render(FrontMatterSplit.split(markdown).body))</main></body>
        </html>
        """
    }

    /// The editor's look at 11 pt, always light, whatever the system appearance. Page margins
    /// come from NSPrintInfo; blocks do not break across pages.
    static func stylesheet(fontFamily: String?) -> String {
        """
        :root { \(DocumentPalette.cssVariables(dark: false)) --check: \(DocumentStyle.checkImage(dark: false)); }
        html { background: white; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body { margin: 0; }
        \(DocumentStyle(fontFamily: fontFamily, fontSize: 11, lineSpacing: 0, lineWidth: nil).css(unit: "pt"))
        h1, h2, h3, h4, h5, h6 { break-after: avoid; }
        pre, blockquote, img, table { break-inside: avoid; }
        """
    }
}
