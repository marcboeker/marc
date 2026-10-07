//
//  SourceHighlighter.swift
//  MarkdownEngine
//
//  Marcdown: light highlighting for raw source mode. Every character stays
//  visible and every line keeps the base font size; syntax markers get the
//  muted color, emphasis and heading text get bold/italic, links and inline
//  code get their theme color.
//

import AppKit
import Foundation

enum SourceHighlighter {
    /// Reset `scope` of `string` to `base`, then highlight the tokens that touch it.
    /// `text` is the string's text; `tokens` and `blocks` come from one parse of it (passed in:
    /// bridging the storage's string is an O(doc) copy). List markers and thematic breaks come
    /// from the engine's AST, so code-block lines get neither.
    static func apply(
        to string: NSMutableAttributedString,
        text: NSString,
        scope: NSRange,
        tokens: [MarkdownToken],
        blocks: [Block],
        base: [NSAttributedString.Key: Any],
        theme: MarkdownEditorTheme
    ) {
        let scope = NSIntersectionRange(scope, NSRange(location: 0, length: text.length))
        guard scope.length > 0 else { return }
        string.setAttributes(base, range: scope)

        func clipped(_ range: NSRange) -> NSRange? {
            let r = NSIntersectionRange(range, scope)
            return r.length > 0 ? r : nil
        }
        func color(_ range: NSRange, _ color: NSColor) {
            if let r = clipped(range) { string.addAttribute(.foregroundColor, value: color, range: r) }
        }
        func add(_ trait: NSFontTraitMask, to range: NSRange) {
            guard let r = clipped(range) else { return }
            string.enumerateAttribute(.font, in: r) { value, run, _ in
                guard let font = value as? NSFont else { return }
                string.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
            }
        }

        var markers: [NSRange] = []
        for token in tokens[candidates(in: tokens, blocks: blocks, scope: scope)]
        where NSIntersectionRange(token.range, scope).length > 0 {
            switch token.kind {
            case .heading, .bold:
                add(.boldFontMask, to: token.contentRange)
            case .italic:
                add(.italicFontMask, to: token.contentRange)
            case .boldItalic:
                add([.boldFontMask, .italicFontMask], to: token.contentRange)
            case .link, .wikiLink:
                color(token.contentRange, theme.link)
            case .inlineCode:
                if let ink = theme.inlineCodeText { color(token.contentRange, ink) }
            case .table:
                markers += pipes(in: NSIntersectionRange(token.range, scope), of: text)
            default:
                break
            }
            markers += token.markerRanges
        }
        markers += lineMarkers(in: scope, of: text, blocks: blocks)
        let muted = theme.mutedText
        for range in markers { color(range, muted) }
    }

    /// Index range of the `tokens` that can touch `scope`. Each block's tokens come together,
    /// inside the block, and blocks tile the document in order; inside a block they are not
    /// sorted (a heading token before its inline tokens), so the cut falls on block bounds.
    private static func candidates(in tokens: [MarkdownToken], blocks: [Block], scope: NSRange) -> Range<Int> {
        guard let first = blocks.firstIndex(endingAfter: scope.location),
              blocks[first].range.location < NSMaxRange(scope) else { return 0..<0 }
        var last = first
        while last + 1 < blocks.count, blocks[last + 1].range.location < NSMaxRange(scope) { last += 1 }
        let start = tokens.partitioningIndex { $0.range.location >= blocks[first].range.location }
        let end = tokens[start...].partitioningIndex { $0.range.location >= NSMaxRange(blocks[last].range) }
        return start..<end
    }

    /// `|` cell separators in the table lines of `range`, and the whole `|---|:---:|` delimiter row.
    private static func pipes(in range: NSRange, of text: NSString) -> [NSRange] {
        var result: [NSRange] = []
        text.enumerateSubstrings(in: text.lineRange(for: range), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            if BlockLevelTokenizer.isTableSeparator(text, line.location, NSMaxRange(line)) {
                result.append(line)
                return
            }
            var search = line
            while search.length > 0 {
                let found = text.range(of: "|", range: search)
                if found.location == NSNotFound { break }
                result.append(found)
                search = NSRange(location: NSMaxRange(found), length: NSMaxRange(line) - NSMaxRange(found))
            }
        }
        return result
    }

    /// List bullets, numbers and task boxes (nested items too: every item line is its own
    /// `ListItem`), and thematic breaks — as the engine's block parser sees them.
    private static func lineMarkers(in scope: NSRange, of text: NSString, blocks: [Block]) -> [NSRange] {
        // Only list and rule blocks: the AST then parses inlines for nothing else.
        let candidates = blocks.filter {
            ($0.kind == .list || $0.kind == .thematicBreak) && NSIntersectionRange($0.range, scope).length > 0
        }
        guard !candidates.isEmpty else { return [] }
        var result: [NSRange] = []
        for node in DocumentAST.parse(text as String, scopedRanges: [scope], precomputedBlocks: candidates) {
            switch node {
            case .list(_, let items):
                for item in items {
                    result.append(item.marker)
                    if let checkbox = item.checkbox { result.append(checkbox) }
                }
            case .thematicBreak(let range):
                result.append(range)
            default:
                break
            }
        }
        return result
    }
}

private extension Array where Element == Block {
    /// First block that ends after `location`, or nil when none does.
    func firstIndex(endingAfter location: Int) -> Int? {
        let i = partitioningIndex { NSMaxRange($0.range) > location }
        return i < endIndex ? i : nil
    }
}

private extension Collection {
    /// First index whose element satisfies `predicate`, which must be false then true along the collection.
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var count = self.count
        while count > 0 {
            let half = count / 2
            let mid = index(low, offsetBy: half)
            if predicate(self[mid]) {
                count = half
            } else {
                low = index(after: mid)
                count -= half + 1
            }
        }
        return low
    }
}
