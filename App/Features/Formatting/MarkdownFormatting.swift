import Foundation
import Markdown

/// A document split into YAML front matter and Markdown body.
/// `front` is verbatim: the opening `---` line through the closing `---` or `...` line,
/// plus any blank lines after it. `front + body == original text`. `front` is empty when there is none.
struct FrontMatterSplit: Equatable {
    var front: String
    var body: String

    /// Front matter needs `---` as the first line and a later line that is exactly `---` or `...`.
    /// Works on UTF-16 because Swift treats `\r\n` as one Character, which breaks line matching.
    static func split(_ text: String) -> FrontMatterSplit {
        let ns = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return FrontMatterSplit(front: "", body: text)
        }
        return FrontMatterSplit(front: ns.substring(to: match.range.length), body: ns.substring(from: match.range.length))
    }

    /// Opening fence, lines up to the closing fence, then blank lines after it.
    private static let pattern = try! NSRegularExpression(pattern: #"\A---\r?\n(?:[^\n]*\n)*?(?:---|\.\.\.)\r?(?:\n|\z)(?:\r?\n)*"#)
}

enum MarkdownFormatting {
    static var options: MarkupFormatter.Options { MarkupFormatter.Options(
        unorderedListMarker: .dash,
        orderedListNumerals: .incrementing(start: 1),
        useCodeFence: .always,
        thematicBreakCharacter: .dash,
        thematicBreakLength: 3,
        emphasisMarker: .star,
        condenseAutolinks: true,
        preferredHeadingStyle: .atx,
        preferredLineLimit: nil
    ) }

    /// Format a whole document for saving. Front matter stays verbatim.
    /// The output ends with exactly one newline (an empty body gives no body text).
    /// `~x~` stays single unless `doublingSingleTildes` (the editor shows only `~~x~~` as strikethrough).
    /// When formatting would change the document's structure, `text` comes back unchanged.
    static func format(_ text: String, doublingSingleTildes: Bool = false) -> String {
        let parts = FrontMatterSplit.split(text)
        let body = formatBody(parts.body, doublingSingleTildes: doublingSingleTildes)
        // swift-markdown prints text without escapes: `\*a\*` would come back as emphasis.
        guard structure(of: body) == structure(of: parts.body) else { return text }
        return parts.front + body
    }

    /// Syntax tree without source positions. List start numbers are left out: the formatter renumbers from 1.
    private static func structure(of markdown: String) -> String {
        Document(parsing: markdown, options: [.disableSmartOpts, .disableSourcePosOpts])
            .debugDescription()
            .replacing(/\ ?startIndex: \d+/, with: "")
    }

    private static func formatBody(_ body: String, doublingSingleTildes: Bool) -> String {
        var document = Document(parsing: body, options: .disableSmartOpts)
        var marker = StrikethroughMarker(source: doublingSingleTildes ? nil : body)
        document = marker.visit(document) as! Document
        let formatted = document.format(options: options)
            .replacingOccurrences(of: StrikethroughMarker.open, with: "~")
            .replacingOccurrences(of: StrikethroughMarker.close, with: "~")
        let trimmed = formatted.trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    /// Map a UTF-16 location to the same line and column in `new`, clamped to the line end.
    static func mapLocation(_ location: Int, from old: String, to new: String) -> Int {
        let location = min(max(location, 0), old.utf16.count)
        let head = (old as NSString).substring(to: location).components(separatedBy: "\n")
        let lines = new.components(separatedBy: "\n")
        let line = head.count - 1
        guard line < lines.count else { return new.utf16.count }
        let lineStart = lines[..<line].reduce(0) { $0 + $1.utf16.count + 1 }
        return lineStart + min(head[line].utf16.count, lines[line].utf16.count)
    }
}

/// swift-markdown prints strikethrough with a single `~`. The editor only knows `~~text~~`,
/// so the formatter also prints private-use markers inside the single `~`, and we swap them for a second `~`.
/// A strikethrough written with a single `~` in `source` gets no markers and stays single.
private struct StrikethroughMarker: MarkupRewriter {
    static let open = "\u{E000}"
    static let close = "\u{E001}"

    /// UTF-8 of the parsed text. Nil: every strikethrough gets a double `~`.
    private let source: [UInt8]?
    private let lineStarts: [Int]

    init(source: String?) {
        let bytes = source.map { Array($0.utf8) }
        var starts = [0]
        for (offset, byte) in (bytes ?? []).enumerated() where byte == UInt8(ascii: "\n") {
            starts.append(offset + 1)
        }
        self.source = bytes
        lineStarts = starts
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> Markup? {
        var children = strikethrough.children.compactMap { visit($0) as? InlineMarkup }
        if isDouble(strikethrough) {
            children.insert(Text(Self.open), at: 0)
            children.append(Text(Self.close))
        }
        return Strikethrough(children)
    }

    private func isDouble(_ strikethrough: Strikethrough) -> Bool {
        guard let source, let start = strikethrough.range?.lowerBound,
              start.line >= 1, start.line <= lineStarts.count
        else { return true }
        let offset = lineStarts[start.line - 1] + start.column - 1
        return offset + 1 < source.count && source[offset + 1] == UInt8(ascii: "~")
    }
}
