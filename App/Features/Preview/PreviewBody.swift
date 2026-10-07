import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// The preview body in top-level blocks, so an edit sends the page only the blocks that changed.
/// A block is one or more top-level cmark nodes that the browser parses the same alone as in the
/// whole page. Raw HTML can open an element in one node and close it nodes later (`<details>`);
/// those nodes stay one block. When unsure, all the rest of the body is one block.
struct PreviewBody: Equatable {
    struct Block: Equatable {
        var html: String
        /// The HTML without source positions: blocks with the same key look the same.
        var key: String
        /// Its `data-sourcepos` values, in document order.
        var positions: [String]

        init(html: String) {
            self.html = html
            let ns = html as NSString
            let matches = PreviewBody.sourcePos.matches(in: html, range: NSRange(location: 0, length: ns.length))
            positions = matches.map { ns.substring(with: $0.range(at: 1)) }
            key = PreviewBody.sourcePos.stringByReplacingMatches(
                in: html, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
    }

    var blocks: [Block]

    static let empty = PreviewBody(blocks: [])

    var html: String { blocks.map(\.html).joined() }

    init(blocks: [Block]) {
        self.blocks = blocks
    }

    /// The same HTML as `MarkdownHTML.render(markdown, sourcePositions: true)`, one top-level node at a time.
    init(markdown: String) {
        let parts: [(html: String, isHTMLBlock: Bool)] = MarkdownHTML.parse(markdown, sourcePositions: true) { document, render in
            var parts: [(html: String, isHTMLBlock: Bool)] = []
            var node = cmark_node_first_child(document)
            while let current = node {
                parts.append((MarkdownHTML.labelLanguages(render(current)), cmark_node_get_type(current) == CMARK_NODE_HTML_BLOCK))
                node = cmark_node_next(current)
            }
            return parts
        } ?? []
        // A new block starts only where nothing is open, and at an element with a source position
        // (the page finds the blocks of a freshly loaded page by it): never at a raw HTML block.
        var htmls: [String] = []
        var open: [String] = []
        var unsure = false
        for part in parts {
            if htmls.isEmpty || open.isEmpty && !unsure && !part.isHTMLBlock {
                htmls.append(part.html)
            } else {
                htmls[htmls.count - 1] += part.html
            }
            if !unsure { unsure = !Self.scan(part.html, open: &open) }
        }
        blocks = htmls.map(Block.init(html:))
    }

    // MARK: Changes

    /// What `marcPreview.update` needs to turn the page's blocks into new ones.
    struct Change: Equatable {
        /// Blocks the page has before.
        var count: Int
        var start: Int
        var removed: Int
        /// The new blocks that go in at `start`.
        var html: [String]
        /// New source positions of kept blocks, by their new index.
        var positions: [Int: [String]]
        /// For a freshly loaded page: the first source position of each block after the first.
        var starts: [String]?
        /// Replace all of the page's body, whatever it has.
        var full = false

        var arguments: [String: Any] {
            [
                "count": count, "start": start, "removed": removed, "html": html,
                "positions": positions.sorted { $0.key < $1.key }.map { [$0.key, $0.value] as [Any] },
                "starts": starts ?? NSNull(), "full": full,
            ]
        }
    }

    /// Keep the unchanged blocks at the start and the end; replace the ones between them.
    /// Kept blocks take the new source positions (lines move when text above changes).
    /// `pageKnowsBlocks` is false for the first change after a load.
    func change(from old: PreviewBody, pageKnowsBlocks: Bool) -> Change {
        let a = old.blocks, b = blocks
        var start = 0
        while start < a.count, start < b.count, a[start].key == b[start].key { start += 1 }
        var end = 0
        while end < a.count - start, end < b.count - start, a[a.count - 1 - end].key == b[b.count - 1 - end].key { end += 1 }
        var positions: [Int: [String]] = [:]
        for i in 0..<start where a[i].positions != b[i].positions {
            positions[i] = b[i].positions
        }
        for k in 0..<end where a[a.count - 1 - k].positions != b[b.count - 1 - k].positions {
            positions[b.count - 1 - k] = b[b.count - 1 - k].positions
        }
        return Change(count: a.count, start: start, removed: a.count - start - end,
                      html: b[start..<(b.count - end)].map(\.html), positions: positions,
                      starts: pageKnowsBlocks ? nil : a.dropFirst().map { $0.positions.first ?? "" })
    }

    /// All blocks, for a page whose blocks are not known (a change failed).
    var full: Change {
        Change(count: 0, start: 0, removed: 0, html: blocks.map(\.html), positions: [:], starts: nil, full: true)
    }

    // MARK: Nesting

    private static let sourcePos = try! NSRegularExpression(pattern: #" data-sourcepos="([^"]*)""#)

    private static let voidElements: Set<String> = [
        "area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr", "img", "input",
        "keygen", "link", "meta", "param", "source", "track", "wbr",
    ]
    /// Their content is text up to their end tag.
    private static let textElements: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes",
    ]
    /// The parser treats them in ways this scan does not follow.
    private static let unsureElements: Set<String> = [
        "html", "head", "body", "frameset", "template", "plaintext", "noscript", "image",
    ]

    /// Follows the elements that `html` opens and closes, after the ones `open` from blocks before.
    /// False when unsure what the browser does: a tag closed out of order, an unclosed comment or tag.
    /// cmark's own HTML always closes what it opens; this is for raw HTML.
    static func scan(_ html: String, open: inout [String]) -> Bool {
        let s = Array(html.utf8)
        let n = s.count
        var i = 0
        while i < n {
            guard s[i] == UInt8(ascii: "<"), i + 1 < n else {
                i += 1
                continue
            }
            let c = s[i + 1]
            if c == UInt8(ascii: "!") {
                if has("<!--", in: s, at: i) {
                    // "<!-->" and "<!--->" end at once.
                    if has(">", in: s, at: i + 4) { i += 5; continue }
                    if has("->", in: s, at: i + 4) { i += 6; continue }
                    guard let end = find("-->", in: s, from: i + 4) else { return false }
                    i = end + 3
                } else if has("<![CDATA[", in: s, at: i) {
                    return false
                } else {
                    guard let end = find(">", in: s, from: i + 2) else { return false }
                    i = end + 1
                }
            } else if c == UInt8(ascii: "?") {
                guard let end = find(">", in: s, from: i + 2) else { return false }
                i = end + 1
            } else if c == UInt8(ascii: "/") {
                guard i + 2 < n else { return false }
                if isLetter(s[i + 2]) {
                    let (name, next) = tagName(s, from: i + 2)
                    guard let (end, _) = skipAttributes(s, from: next) else { return false }
                    i = end
                    guard open.last == name else { return false }
                    open.removeLast()
                } else {
                    // "</>" is dropped, "</ x>" is a comment.
                    guard let end = find(">", in: s, from: i + 2) else { return false }
                    i = end + 1
                }
            } else if isLetter(c) {
                let (name, next) = tagName(s, from: i + 1)
                guard let (end, selfClosing) = skipAttributes(s, from: next) else { return false }
                i = end
                if unsureElements.contains(name) { return false }
                if voidElements.contains(name) { continue }
                // Only SVG and MathML elements close themselves with "/>".
                if selfClosing, name == "svg" || name == "math" || open.contains("svg") || open.contains("math") { continue }
                open.append(name)
                if textElements.contains(name) {
                    guard let close = findEndTag(name, in: s, from: i) else { return false }
                    if name == "script", find("<!--", in: s, from: i).map({ $0 < close }) ?? false { return false }
                    i = close
                }
            } else {
                i += 1
            }
        }
        return true
    }

    private static func isLetter(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }

    private static func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D
    }

    private static func lower(_ b: UInt8) -> UInt8 {
        b >= 0x41 && b <= 0x5A ? b + 0x20 : b
    }

    /// `text` (ASCII) at `index`, in any case.
    private static func has(_ text: String, in s: [UInt8], at index: Int) -> Bool {
        has(Array(text.utf8), in: s, at: index)
    }

    private static func has(_ t: [UInt8], in s: [UInt8], at index: Int) -> Bool {
        guard index + t.count <= s.count else { return false }
        for k in 0..<t.count where lower(s[index + k]) != lower(t[k]) { return false }
        return true
    }

    private static func find(_ text: String, in s: [UInt8], from index: Int) -> Int? {
        let t = Array(text.utf8)
        var k = index
        while k < s.count {
            if has(t, in: s, at: k) { return k }
            k += 1
        }
        return nil
    }

    /// Lowercased name, and the index after it.
    private static func tagName(_ s: [UInt8], from index: Int) -> (String, Int) {
        var k = index
        while k < s.count, !isSpace(s[k]), s[k] != UInt8(ascii: "/"), s[k] != UInt8(ascii: ">") { k += 1 }
        return (String(decoding: s[index..<k].map(lower), as: UTF8.self), k)
    }

    /// The index after the tag's ">", and whether it ends with "/>". Nil for a tag without an end.
    /// Like the browser: quoted values can hold ">", a value without quotes ends at a space.
    private static func skipAttributes(_ s: [UInt8], from index: Int) -> (Int, Bool)? {
        let n = s.count
        var k = index
        while k < n {
            let b = s[k]
            if b == UInt8(ascii: ">") { return (k + 1, false) }
            if b == UInt8(ascii: "/") {
                if k + 1 < n, s[k + 1] == UInt8(ascii: ">") { return (k + 2, true) }
                k += 1
                continue
            }
            if isSpace(b) { k += 1; continue }
            // A name; its first character can be "=".
            k += 1
            while k < n, !isSpace(s[k]), s[k] != UInt8(ascii: "/"), s[k] != UInt8(ascii: ">"), s[k] != UInt8(ascii: "=") { k += 1 }
            while k < n, isSpace(s[k]) { k += 1 }
            guard k < n, s[k] == UInt8(ascii: "=") else { continue }
            k += 1
            while k < n, isSpace(s[k]) { k += 1 }
            guard k < n else { return nil }
            if s[k] == UInt8(ascii: "\"") || s[k] == UInt8(ascii: "'") {
                let quote = s[k]
                k += 1
                while k < n, s[k] != quote { k += 1 }
                guard k < n else { return nil }
                k += 1
            } else {
                while k < n, !isSpace(s[k]), s[k] != UInt8(ascii: ">") { k += 1 }
            }
        }
        return nil
    }

    /// Start of the end tag of a text element: "</name" and then a space, "/" or ">".
    private static func findEndTag(_ name: String, in s: [UInt8], from index: Int) -> Int? {
        var k = index
        while let found = find("</" + name, in: s, from: k) {
            let after = found + 2 + name.utf8.count
            if after < s.count, isSpace(s[after]) || s[after] == UInt8(ascii: "/") || s[after] == UInt8(ascii: ">") { return found }
            k = found + 1
        }
        return nil
    }
}
