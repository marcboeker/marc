import Foundation

/// Text plus selection. All ranges are UTF-16 (`NSRange`), as in `NSTextView`.
struct TextEdit: Equatable {
    var text: String
    var selection: NSRange
}

/// Pure toggle edits on raw Markdown. Each function returns the new text and selection.
enum MarkdownEdits {

    // MARK: Line-level

    /// A line's block kind; `.paragraph` is a line without a prefix.
    enum LineTarget: Equatable {
        case heading(Int)
        case paragraph
        case quote
        case bullet
        case numbered
        case task

        var isList: Bool { self == .bullet || self == .task || self == .numbered }
    }

    private struct Line {
        var range: NSRange          // includes the terminator
        var kind: LineTarget
        var indent: String
        var prefix: String          // whole old prefix, indent included
        var body: String
        var terminator: String
        var isBlank: Bool { kind == .paragraph && body.allSatisfy(\.isWhitespace) }
    }

    /// Heading, paragraph, quote and list toggles on every line touched by the selection.
    static func line(_ target: LineTarget, _ edit: TextEdit) -> TextEdit {
        let ns = edit.text as NSString
        let block = lineBlock(ns, edit.selection)
        let lines = splitLines(ns, block)

        let nonBlank = lines.filter { !$0.isBlank }
        let removing: Bool
        switch target {
        case .paragraph: removing = true
        default: removing = !nonBlank.isEmpty && nonBlank.allSatisfy { $0.kind == target }
        }
        let affected: [Line] = nonBlank.isEmpty ? lines : nonBlank

        var newPrefixes: [Int: String] = [:]   // by location
        var ordinal = 0
        for line in affected {
            if removing {
                newPrefixes[line.range.location] = ""
                continue
            }
            ordinal += 1
            if line.kind == target, target != .numbered {
                newPrefixes[line.range.location] = line.prefix
                continue
            }
            let indent = line.kind.isList ? line.indent : ""
            switch target {
            case .heading(let level): newPrefixes[line.range.location] = String(repeating: "#", count: level) + " "
            case .quote: newPrefixes[line.range.location] = "> "
            case .bullet: newPrefixes[line.range.location] = indent + "- "
            case .task: newPrefixes[line.range.location] = indent + "- [ ] "
            case .numbered: newPrefixes[line.range.location] = indent + "\(ordinal). "
            case .paragraph: newPrefixes[line.range.location] = ""
            }
        }

        // Rebuild the block and record how each line's prefix changed.
        var rebuilt = ""
        var spans: [(oldStart: Int, oldPrefix: Int, newStart: Int, newPrefix: Int)] = []
        for line in lines {
            let newPrefix = newPrefixes[line.range.location] ?? line.prefix
            let newStart = block.location + (rebuilt as NSString).length
            spans.append((line.range.location, (line.prefix as NSString).length, newStart, (newPrefix as NSString).length))
            rebuilt += newPrefix + line.body + line.terminator
        }
        let newBlockEnd = block.location + (rebuilt as NSString).length

        // A range that starts at a line start keeps the whole line selected, so the prefix stays inside it.
        func map(_ p: Int, isRangeStart: Bool = false) -> Int {
            if p >= NSMaxRange(block), !(block.length == 0 && p == block.location) { return newBlockEnd + (p - NSMaxRange(block)) }
            guard let span = spans.last(where: { $0.oldStart <= p }) else { return p }
            let offset = p - span.oldStart
            if isRangeStart, offset == 0 { return span.newStart }
            return offset <= span.oldPrefix ? span.newStart + span.newPrefix : span.newStart + span.newPrefix + (offset - span.oldPrefix)
        }
        let start = map(edit.selection.location, isRangeStart: edit.selection.length > 0)
        let end = map(NSMaxRange(edit.selection))
        return TextEdit(text: ns.replacingCharacters(in: block, with: rebuilt),
                        selection: NSRange(location: start, length: max(0, end - start)))
    }

    /// Full lines touched by the selection. A non-empty selection that ends at a line start
    /// does not touch that next line.
    private static func lineBlock(_ ns: NSString, _ sel: NSRange) -> NSRange {
        let first = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let lastLocation = sel.length > 0 ? max(sel.location, NSMaxRange(sel) - 1) : sel.location
        let last = ns.lineRange(for: NSRange(location: lastLocation, length: 0))
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private static func splitLines(_ ns: NSString, _ block: NSRange) -> [Line] {
        if block.length == 0 { return [parseLine(ns, block)] }
        var lines: [Line] = []
        var location = block.location
        while location < NSMaxRange(block) {
            let range = ns.lineRange(for: NSRange(location: location, length: 0))
            lines.append(parseLine(ns, range))
            location = NSMaxRange(range)
        }
        return lines
    }

    private static func parseLine(_ ns: NSString, _ range: NSRange) -> Line {
        var contentRange = range
        var contentEnd = NSMaxRange(range)
        ns.getLineStart(nil, end: nil, contentsEnd: &contentEnd, for: range)
        contentRange.length = contentEnd - range.location
        let content = ns.substring(with: contentRange)
        let bytes = Array(content.utf8)
        let (kind, prefixLength, indentLength) = parsePrefix(bytes)
        return Line(range: range, kind: kind,
                    indent: String(decoding: bytes[0..<indentLength], as: UTF8.self),
                    prefix: String(decoding: bytes[0..<prefixLength], as: UTF8.self),
                    body: String(decoding: bytes[prefixLength...], as: UTF8.self),
                    terminator: ns.substring(with: NSRange(location: contentEnd, length: NSMaxRange(range) - contentEnd)))
    }

    /// The prefix is ASCII, so byte counts equal UTF-16 counts.
    private static func parsePrefix(_ u: [UInt8]) -> (LineTarget, prefix: Int, indent: Int) {
        let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
        func isBlank(_ i: Int) -> Bool { i < u.count && (u[i] == space || u[i] == tab) }
        var s = 0
        while isBlank(s) { s += 1 }
        guard s < u.count else { return (.paragraph, 0, 0) }

        switch u[s] {
        case UInt8(ascii: "#"):
            var n = 0
            while s + n < u.count, u[s + n] == UInt8(ascii: "#") { n += 1 }
            if (1...6).contains(n), isBlank(s + n) {
                var p = s + n
                while isBlank(p) { p += 1 }
                return (.heading(n), p, 0)
            }
        case UInt8(ascii: ">"):
            return (.quote, s + 1 + (isBlank(s + 1) ? 1 : 0), 0)
        case UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+"):
            if isBlank(s + 1) {
                let p = s + 2
                if p + 2 < u.count, u[p] == UInt8(ascii: "["),
                   [space, UInt8(ascii: "x"), UInt8(ascii: "X")].contains(u[p + 1]), u[p + 2] == UInt8(ascii: "]"),
                   p + 3 == u.count || isBlank(p + 3) {
                    return (.task, min(p + 4, u.count), s)
                }
                return (.bullet, p, s)
            }
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            var p = s
            while p < u.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(u[p]) { p += 1 }
            if p - s <= 9, p < u.count, u[p] == UInt8(ascii: ".") || u[p] == UInt8(ascii: ")"), isBlank(p + 1) {
                return (.numbered, p + 2, s)
            }
        default: break
        }
        return (.paragraph, 0, 0)
    }

    // MARK: Inline

    /// Toggle an inline marker (`**`, `*`, `~~`, `` ` ``) around the selection or the word at the cursor.
    static func inline(_ marker: String, _ edit: TextEdit) -> TextEdit {
        let ns = edit.text as NSString
        let k = marker.utf16.count
        let c = marker.utf16.first!
        let cursor = edit.selection.location

        var target = trimmed(ns, edit.selection)
        let wasEmpty = target.length == 0
        if wasEmpty {
            guard let word = wordRange(ns, at: cursor) else {
                let text = ns.replacingCharacters(in: NSRange(location: cursor, length: 0), with: marker + marker)
                return TextEdit(text: text, selection: NSRange(location: cursor + k, length: 0))
            }
            target = word
        }

        func run(from: Int, step: Int, within: Range<Int>) -> Int {
            var n = 0, i = from
            while within.contains(i), ns.character(at: i) == c { n += 1; i += step }
            return n
        }
        func present(_ n: Int) -> Bool { c == UInt16(UInt8(ascii: "*")) && k == 1 ? n % 2 == 1 : n >= k }

        var insideLeft = run(from: target.location, step: 1, within: target.location..<NSMaxRange(target))
        var insideRight = run(from: NSMaxRange(target) - 1, step: -1, within: target.location..<NSMaxRange(target))
        if insideLeft == target.length { insideLeft = 0; insideRight = 0 }
        let outsideLeft = run(from: target.location - 1, step: -1, within: 0..<ns.length)
        let outsideRight = run(from: NSMaxRange(target), step: 1, within: 0..<ns.length)

        var text: String
        var newTarget: NSRange
        if present(min(insideLeft, insideRight)) {
            text = ns.replacingCharacters(in: NSRange(location: NSMaxRange(target) - k, length: k), with: "")
            text = (text as NSString).replacingCharacters(in: NSRange(location: target.location, length: k), with: "")
            newTarget = NSRange(location: target.location, length: target.length - 2 * k)
        } else if present(min(outsideLeft, outsideRight)) {
            text = ns.replacingCharacters(in: NSRange(location: NSMaxRange(target), length: k), with: "")
            text = (text as NSString).replacingCharacters(in: NSRange(location: target.location - k, length: k), with: "")
            newTarget = NSRange(location: target.location - k, length: target.length)
        } else {
            let inner = ns.substring(with: target)
            text = ns.replacingCharacters(in: target, with: marker + inner + marker)
            newTarget = NSRange(location: target.location + k, length: target.length)
        }
        if wasEmpty {
            return TextEdit(text: text, selection: NSRange(location: cursor + newTarget.location - target.location, length: 0))
        }
        return TextEdit(text: text, selection: newTarget)
    }

    /// The selection without surrounding whitespace. Empty when only whitespace is selected.
    private static func trimmed(_ ns: NSString, _ sel: NSRange) -> NSRange {
        var start = sel.location, end = NSMaxRange(sel)
        func isSpace(_ i: Int) -> Bool { CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: i)) ?? "a") }
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return start == end ? NSRange(location: sel.location, length: 0) : NSRange(location: start, length: end - start)
    }

    /// The run of letters, marks and digits around `location`.
    static func wordRange(_ ns: NSString, at location: Int) -> NSRange? {
        func isWord(_ i: Int) -> Bool {
            i >= 0 && i < ns.length && CharacterSet.alphanumerics.contains(UnicodeScalar(ns.character(at: i)) ?? " ")
        }
        var start = location, end = location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    // MARK: Link

    /// Wrap the selection as a link, or unwrap when the selection is inside a link.
    /// `url` is the pasteboard URL, if any.
    static func link(_ edit: TextEdit, url: String?) -> TextEdit {
        let ns = edit.text as NSString
        let sel = edit.selection

        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        for match in linkPattern.matches(in: edit.text, range: lineRange) {
            let m = match.range
            guard m.location <= sel.location, NSMaxRange(sel) <= NSMaxRange(m) else { continue }
            let label = match.range(at: 1)
            let text = ns.replacingCharacters(in: m, with: ns.substring(with: label))
            if sel.length == 0 {
                let inside = min(max(sel.location - label.location, 0), label.length)
                return TextEdit(text: text, selection: NSRange(location: m.location + inside, length: 0))
            }
            return TextEdit(text: text, selection: NSRange(location: m.location, length: label.length))
        }

        var target = trimmed(ns, sel)
        if target.length == 0 {
            if let word = wordRange(ns, at: sel.location) {
                target = word
            } else {
                let destination = url ?? "url"
                let text = ns.replacingCharacters(in: target, with: "[](\(destination))")
                return TextEdit(text: text, selection: NSRange(location: target.location + 1, length: 0))
            }
        }
        let label = ns.substring(with: target)
        let text = ns.replacingCharacters(in: target, with: "[\(label)](\(url ?? "url"))")
        let afterLabel = target.location + target.length + 3   // "[" + label + "]("
        if let url {
            return TextEdit(text: text, selection: NSRange(location: afterLabel + url.utf16.count + 1, length: 0))
        }
        return TextEdit(text: text, selection: NSRange(location: afterLabel, length: 3))
    }

    private static let linkPattern = try! NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]*)\]\(([^)\n]*)\)"#)

    // MARK: Code block

    /// Wrap the touched lines in ``` fences, or remove the fences when the cursor is inside a fenced block.
    static func codeBlock(_ edit: TextEdit) -> TextEdit {
        let ns = edit.text as NSString
        let block = lineBlock(ns, edit.selection)

        if let fenced = fencedBlocks(ns).first(where: { fence in
            // An unclosed fence runs to the end of the text, the end included.
            let end = fence.close.map(NSMaxRange) ?? ns.length + 1
            return (fence.open.location..<end).contains(block.location)
        }) {
            func shrink(_ p: Int, _ r: NSRange) -> Int {
                p <= r.location ? p : p >= NSMaxRange(r) ? p - r.length : r.location
            }
            var text = ns as String
            var removals = [fenced.open]
            if let close = fenced.close { removals.insert(close, at: 0) }   // later range first
            for r in removals { text = (text as NSString).replacingCharacters(in: r, with: "") }
            func map(_ p: Int) -> Int { removals.reduce(p, shrink) }
            let start = map(edit.selection.location)
            return TextEdit(text: text, selection: NSRange(location: start, length: map(NSMaxRange(edit.selection)) - start))
        }

        let endsWithNewline = block.length > 0 && ns.character(at: NSMaxRange(block) - 1) == 10
        let body = ns.substring(with: block)
        let wrapped = "```\n" + body + (endsWithNewline ? "" : "\n") + "```" + (endsWithNewline ? "\n" : "")
        let text = ns.replacingCharacters(in: block, with: wrapped)
        return TextEdit(text: text, selection: NSRange(location: edit.selection.location + 4, length: edit.selection.length))
    }

    /// Fenced blocks as (opening line range, closing line range or nil when unclosed). Ranges include terminators.
    private static func fencedBlocks(_ ns: NSString) -> [(open: NSRange, close: NSRange?)] {
        var result: [(open: NSRange, close: NSRange?)] = []
        var open: (range: NSRange, char: Character, count: Int)?
        var location = 0
        while location < ns.length {
            let range = ns.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            let line = ns.substring(with: range).trimmingCharacters(in: .newlines)
            let stripped = line.drop { $0 == " " }
            guard line.count - stripped.count <= 3, let char = stripped.first, char == "`" || char == "~" else { continue }
            let count = stripped.prefix { $0 == char }.count
            guard count >= 3 else { continue }
            let rest = stripped.dropFirst(count)
            if let current = open {
                if char == current.char, count >= current.count, rest.allSatisfy(\.isWhitespace) {
                    result.append((current.range, range))
                    open = nil
                }
            } else if !(char == "`" && rest.contains("`")) {
                open = (range, char, count)
            }
        }
        if let open { result.append((open.range, nil)) }
        return result
    }

    // MARK: Rule

    /// Insert `---` on its own line with blank lines around it.
    static func rule(_ edit: TextEdit) -> TextEdit {
        let ns = edit.text as NSString
        let sel = edit.selection
        let lastLocation = sel.length > 0 ? max(sel.location, NSMaxRange(sel) - 1) : sel.location
        let block = ns.lineRange(for: NSRange(location: lastLocation, length: 0))
        var contentEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentEnd, for: block)
        let hasTerminator = contentEnd < NSMaxRange(block)
        let content = ns.substring(with: NSRange(location: block.location, length: contentEnd - block.location))
        let next: String? = NSMaxRange(block) < ns.length
            ? ns.substring(with: ns.lineRange(for: NSRange(location: NSMaxRange(block), length: 0)))
            : nil
        let nextIsBlank = next.map { $0.allSatisfy(\.isWhitespace) } ?? false
        let extraNewline = !hasTerminator || (next != nil && !nextIsBlank)

        if content.allSatisfy(\.isWhitespace) {
            var previousIsBlank = true
            if block.location > 0 {
                let previous = ns.substring(with: ns.lineRange(for: NSRange(location: block.location - 1, length: 0)))
                previousIsBlank = previous.allSatisfy(\.isWhitespace)
            }
            let prefix = previousIsBlank ? "" : "\n"
            let replacement = prefix + "---" + (extraNewline ? "\n" : "")
            let range = NSRange(location: block.location, length: contentEnd - block.location)
            return TextEdit(text: ns.replacingCharacters(in: range, with: replacement),
                            selection: NSRange(location: block.location + prefix.utf16.count + 4, length: 0))
        }
        let insertion = "\n\n---" + (extraNewline ? "\n" : "")
        let text = ns.replacingCharacters(in: NSRange(location: contentEnd, length: 0), with: insertion)
        return TextEdit(text: text, selection: NSRange(location: contentEnd + 6, length: 0))
    }

    // MARK: Minimal replacement

    /// The smallest single replacement that turns `old` into `new`. Nil when equal.
    static func replacement(from old: String, to new: String) -> (range: NSRange, text: String)? {
        let a = old as NSString, b = new as NSString
        var prefix = 0
        let limit = min(a.length, b.length)
        while prefix < limit, a.character(at: prefix) == b.character(at: prefix) { prefix += 1 }
        if prefix == a.length, prefix == b.length { return nil }
        if prefix > 0, UTF16.isLeadSurrogate(a.character(at: prefix - 1)) { prefix -= 1 }
        var suffix = 0
        while suffix < limit - prefix, a.character(at: a.length - 1 - suffix) == b.character(at: b.length - 1 - suffix) { suffix += 1 }
        if suffix > 0, UTF16.isTrailSurrogate(a.character(at: a.length - suffix)) { suffix -= 1 }
        let range = NSRange(location: prefix, length: a.length - prefix - suffix)
        return (range, b.substring(with: NSRange(location: prefix, length: b.length - prefix - suffix)))
    }
}
