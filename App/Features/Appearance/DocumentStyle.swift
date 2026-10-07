import AppKit
import MarkdownEngine

/// Marcdown's look for a Markdown document, shared by the editor, the Preview and Print. The colors
/// are one palette, and the measures are computed once from the font, so the editor's paragraph
/// styles and the pages' CSS put text, gaps and blocks at the same places.
struct DocumentStyle: Equatable {
    /// Family name, or nil for the system font.
    var fontFamily: String?
    var fontSize: CGFloat
    /// Extra points per line, on top of the base line height.
    var lineSpacing: CGFloat
    /// Longest line in characters (widths of "0"), or nil for the full width.
    var lineWidth: Int?

    // MARK: Ratios, in ems of the body font

    static let lineHeightFactor: CGFloat = 1.4
    static let headingScale: [CGFloat] = [1.75, 1.35, 1.15, 1, 1, 1]
    /// Levels from this one down draw in the secondary color, at body size.
    static let mutedHeadingLevel = 5
    static let blockGapFactor: CGFloat = 0.85
    static let headingAboveFactor: CGFloat = 1.9
    static let itemGapFactor: CGFloat = 0.2
    /// Where a top-level list item's text starts.
    static let listIndentFactor: CGFloat = 1.6
    static let codeScale: CGFloat = 0.88
    /// How far code and quote panels reach left and right of the text column.
    static let outsetFactor: CGFloat = 0.75
    static let quotePaddingFactor: CGFloat = 0.45

    // MARK: Measures, in points

    var font: NSFont {
        fontFamily.flatMap { NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: fontSize) }
            ?? .systemFont(ofSize: fontSize)
    }

    /// The editor's line height before `lineSpacing` (MarkdownEngine: ascender − descender + leading).
    var naturalLineHeight: CGFloat {
        let font = font
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// Distance from one body line to the next.
    var lineHeight: CGFloat { max(naturalLineHeight, (fontSize * Self.lineHeightFactor).rounded()) + lineSpacing }
    /// Space below a paragraph, list, quote, code block or table.
    var gap: CGFloat { (fontSize * Self.blockGapFactor).rounded() }
    var headingAbove: CGFloat { (fontSize * Self.headingAboveFactor).rounded() }
    var itemGap: CGFloat { (fontSize * Self.itemGapFactor).rounded() }
    var outset: CGFloat { (fontSize * Self.outsetFactor).rounded() }
    var quotePadding: CGFloat { (fontSize * Self.quotePaddingFactor).rounded() }
    var listIndent: CGFloat { (fontSize * Self.listIndentFactor).rounded() }

    func headingSize(_ level: Int) -> CGFloat {
        (fontSize * Self.headingScale[min(max(level, 1), 6) - 1]).rounded()
    }

    /// Where a top-level bullet starts, so its text starts at `listIndent`.
    var markerIndent: CGFloat { max(0, listIndent - width("- ")) }

    /// Width of one character ("0"), as CSS `ch`.
    var characterWidth: CGFloat { width("0") }

    /// Width of the text column, or nil for the full width.
    var columnWidth: CGFloat? { lineWidth.map { (CGFloat($0) * characterWidth).rounded() } }

    func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

// MARK: - Editor

extension DocumentStyle {
    /// Sets the editor's measures and colors. The text inset (and so the column) is the caller's.
    func apply(to config: inout MarkdownEditorConfiguration) {
        config.theme = .marcdown
        let extra = lineHeight - naturalLineHeight
        config.paragraph.lineHeightExtraSpacing = extra
        config.lists.extraLineHeight = extra
        config.blockquote.extraLineHeight = extra
        // In the source, blocks are apart by an empty line: that line is the gap. No block adds
        // space below itself, and the lines of one paragraph sit at line pitch.
        config.paragraph.blankLineHeight = gap
        config.paragraph.spacingFactor = 0

        config.headings.fontMultipliers = Self.headingScale
        // The space above a heading adds to the empty line before it; CSS margins collapse
        // instead. Both end at `headingAbove`.
        config.headings.topSpacingEm = (1...6).map { (headingAbove - gap) / headingSize($0) }
        config.headings.mutedFromLevel = Self.mutedHeadingLevel

        config.lists.indentPerLevel = listIndent
        config.lists.markerIndent = markerIndent
        config.lists.itemSpacing = itemGap

        config.codeBlock.fontSizeScale = Self.codeScale
        config.inlineCode.fontSizeScale = Self.codeScale
        config.codeBlock.paragraphSpacing = 2
        // Code lines up with the body text; the slab reaches into the inset instead.
        config.codeBlock.horizontalIndent = 0
        config.codeBlock.backgroundOutset = outset
        config.blockquote.panelPadding = quotePadding
    }
}

extension MarkdownEditorTheme {
    /// Marcdown's look: the DocumentStyle palette.
    static let marcdown = MarkdownEditorTheme(
        bodyText: DocumentPalette.text.color,
        mutedText: DocumentPalette.secondary.color,
        disabledText: DocumentPalette.tertiary.color,
        headingMarker: DocumentPalette.tertiary.color,
        link: DocumentPalette.link.color,
        strikethroughColor: DocumentPalette.tertiary.color,
        highlightColor: DocumentPalette.mark.color,
        codeBlockBackground: DocumentPalette.surface.color,
        codeBlockLanguage: DocumentPalette.tertiary.color,
        inlineCodeBackground: DocumentPalette.codeFill.color,
        inlineCodeText: DocumentPalette.code.color,
        blockquoteBar: DocumentPalette.bar.color,
        blockquoteBackground: DocumentPalette.surface.color,
        blockquoteText: DocumentPalette.secondary.color,
        tableBorder: DocumentPalette.rule.color,
        tableHeaderRule: DocumentPalette.strongRule.color,
        rule: DocumentPalette.rule.color,
        listMarker: DocumentPalette.tertiary.color,
        linkUnderline: DocumentPalette.linkUnderline.color,
        taskDoneText: DocumentPalette.secondary.color
    )
}

// MARK: - Palette

/// One color in a light and a dark appearance.
struct DocumentInk {
    let light: (red: Int, green: Int, blue: Int, alpha: CGFloat)
    let dark: (red: Int, green: Int, blue: Int, alpha: CGFloat)

    /// Follows the view's appearance.
    var color: NSColor {
        let light = light, dark = dark
        return NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255,
                           blue: CGFloat(c.blue) / 255, alpha: c.alpha)
        }
    }

    func css(dark: Bool) -> String {
        let c = dark ? self.dark : light
        return "rgba(\(c.red), \(c.green), \(c.blue), \(String(format: "%g", Double(c.alpha))))"
    }
}

enum DocumentPalette {
    static let text = DocumentInk(light: (29, 29, 31, 1), dark: (255, 255, 255, 0.87))
    static let secondary = DocumentInk(light: (107, 107, 112, 1), dark: (255, 255, 255, 0.58))
    static let tertiary = DocumentInk(light: (148, 148, 154, 1), dark: (255, 255, 255, 0.38))
    static let rule = DocumentInk(light: (0, 0, 0, 0.12), dark: (255, 255, 255, 0.13))
    static let strongRule = DocumentInk(light: (0, 0, 0, 0.4), dark: (255, 255, 255, 0.4))
    static let bar = DocumentInk(light: (0, 0, 0, 0.2), dark: (255, 255, 255, 0.22))
    static let surface = DocumentInk(light: (0, 0, 0, 0.04), dark: (255, 255, 255, 0.055))
    static let link = DocumentInk(light: (10, 95, 194, 1), dark: (108, 182, 255, 1))
    static let linkUnderline = DocumentInk(light: (10, 95, 194, 0.4), dark: (108, 182, 255, 0.4))
    static let code = DocumentInk(light: (184, 68, 12, 1), dark: (255, 154, 92, 1))
    static let codeFill = DocumentInk(light: (255, 106, 26, 0.09), dark: (255, 106, 26, 0.11))
    static let mark = DocumentInk(light: (255, 106, 26, 0.28), dark: (255, 106, 26, 0.32))

    /// Name → color, as the pages' CSS custom properties (`--text`, …).
    static let all: [(name: String, ink: DocumentInk)] = [
        ("text", text), ("secondary", secondary), ("tertiary", tertiary), ("rule", rule),
        ("strong-rule", strongRule), ("bar", bar), ("surface", surface), ("link", link),
        ("link-underline", linkUnderline), ("code", code), ("code-fill", codeFill), ("mark", mark),
    ]

    static func cssVariables(dark: Bool) -> String {
        all.map { "--\($0.name): \($0.ink.css(dark: dark));" }.joined(separator: " ")
    }
}

// MARK: - Pages

extension DocumentStyle {
    /// The document rules of the Preview and Print pages, in `unit` (`px` on screen, `pt` on
    /// paper). The page sets the colors (`DocumentPalette.cssVariables`) and its own frame.
    func css(unit u: String) -> String {
        func n(_ value: CGFloat) -> String { "\(Int(value.rounded()))\(u)" }
        // The editor's code line: the system mono font at the rounded code size, plus 2 points
        // of paragraph spacing above and below (CodeBlockStyle.paragraphSpacing).
        let codeFont = NSFont.monospacedSystemFont(ofSize: (fontSize * Self.codeScale).rounded(), weight: .regular)
        let codeLine = ceil(codeFont.ascender - codeFont.descender + codeFont.leading)
        let mono = "ui-monospace, Menlo, monospace"
        let nested = width("  ")
        return """
        :root { font-family: \(MarkdownHTML.fontFamily(fontFamily)); font-size: \(n(fontSize)); }
        html { color: var(--text); }
        main { \(columnWidth.map { "max-width: \(n($0)); " } ?? "")margin: 0 auto; overflow-wrap: break-word; }
        main > :first-child { margin-top: 0; }
        p, ul, ol, blockquote, pre, table, details { margin: 0 0 \(n(gap)); }
        p, li, blockquote, dt, dd, summary { line-height: \(n(lineHeight)); }
        h1, h2, h3, h4, h5, h6 { margin: \(n(headingAbove)) 0 \(n(gap)); line-height: 1.3; font-weight: 700; }
        h1 { font-size: \(n(headingSize(1))); } h2 { font-size: \(n(headingSize(2))); } h3 { font-size: \(n(headingSize(3))); }
        h4, h5, h6 { font-size: 1em; } h5, h6 { color: var(--secondary); }
        a { color: var(--link); text-decoration: underline 1px var(--link-underline); text-underline-offset: 0.2em; }
        a:hover { text-decoration-color: var(--link); }
        ul, ol { padding-left: \(n(listIndent)); }
        li > ul, li > ol { padding-left: \(n(nested)); margin: \(n(itemGap)) 0 0; }
        ul, ul ul, ul ul ul { list-style-type: disc; }
        li { margin: 0 0 \(n(itemGap)); } li:last-child { margin-bottom: 0; }
        li::marker { color: var(--tertiary); }
        li > p { margin: 0; } li > p + p { margin-top: \(n(gap)); } li:has(> p) { margin-bottom: \(n(gap)); }
        li:has(> input[type=checkbox]) { list-style: none; }
        li:has(> input[type=checkbox]:checked) { color: var(--secondary); text-decoration: line-through var(--tertiary); }
        li > input[type=checkbox] { appearance: none; font: inherit; box-sizing: border-box; width: 0.95em; height: 0.95em;
            margin: 0 0.35em 0 -1.3em; vertical-align: -0.12em; border: 1.5px solid var(--tertiary); border-radius: 0.2em; }
        li > input[type=checkbox]:checked { border-color: var(--tertiary); background: var(--tertiary) var(--check) center / 80% no-repeat; }
        code, pre, kbd { font-family: \(mono); }
        code { font-size: \(Self.codeScale)em; color: var(--code); background: var(--code-fill); border-radius: 4px;
            padding: 0.08em 0.3em; -webkit-box-decoration-break: clone; box-decoration-break: clone; }
        pre { position: relative; background: var(--surface); border-radius: 8px; margin-left: -\(n(outset)); margin-right: -\(n(outset));
            padding: \(n(codeLine + 4)) \(n(outset)); line-height: \(n(codeLine + 4)); font-size: \(Self.codeScale)em;
            white-space: pre-wrap; overflow-wrap: anywhere; }
        pre code { font-size: 1em; color: inherit; background: none; padding: 0; }
        pre[data-lang]::before { content: attr(data-lang); position: absolute; top: 0; right: \(n(outset));
            line-height: \(n(codeLine + 4)); font-size: 0.85em; color: var(--tertiary); }
        blockquote { color: var(--secondary); background: var(--surface); border-radius: 8px; box-shadow: inset 2px 0 0 var(--bar);
            margin-left: -\(n(outset)); margin-right: -\(n(outset)); padding: \(n(quotePadding)) \(n(outset)); }
        blockquote > * { margin: 0 0 \(n(lineHeight)); } blockquote > :last-child { margin-bottom: 0; }
        blockquote blockquote { background: none; border-radius: 0; margin: 0 0 \(n(lineHeight));
            padding: 0 0 0 \(n(20)); box-shadow: inset 2px 0 0 var(--bar); }
        blockquote ul, blockquote ol { padding-left: \(n(width("- "))); }
        blockquote pre { background: none; margin: 0; padding: 0; }
        blockquote pre[data-lang]::before { content: none; }
        table { border-collapse: collapse; font-variant-numeric: tabular-nums; display: block; max-width: 100%; overflow-x: auto; }
        th, td { padding: 6\(u) 12\(u); border-bottom: 1px solid var(--rule); text-align: left; vertical-align: top; }
        th:first-child, td:first-child { padding-left: 0; } th:last-child, td:last-child { padding-right: 0; }
        th { font-weight: 700; border-bottom-color: var(--strong-rule); }
        [align=center] { text-align: center; } [align=right] { text-align: right; }
        hr { border: none; border-top: 1px solid var(--rule); margin: \(n(gap + lineHeight / 2)) 0; }
        img { max-width: 100%; }
        del { text-decoration-color: var(--tertiary); }
        mark { background: var(--mark); color: inherit; border-radius: 3px; padding: 0 0.1em; }
        kbd { font-size: 0.8em; padding: 0.05em 0.4em; border: 1px solid var(--rule); border-bottom-width: 2px; border-radius: 0.3em; }
        summary { color: var(--secondary); cursor: pointer; }
        """
    }

    /// `--check`: the tick inside a checked task box, in the page background's color.
    static func checkImage(dark: Bool) -> String {
        let stroke = dark ? "%231f1f1f" : "white"
        return "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>"
            + "<path d='M3.5 8.5l3 3 6-7' fill='none' stroke='\(stroke)' stroke-width='2.2' "
            + "stroke-linecap='round' stroke-linejoin='round'/></svg>\")"
    }
}
