import Foundation

/// 3-way merge (diff3). Pure, so it can be tested without a window.
/// Lines merge first; a chunk both sides changed is merged again word by word, so edits to
/// different words of one paragraph line still merge cleanly. What is left gets conflict markers:
/// inline (`👤 mine 🔀 disk 💾`) when both sides fit on one line, else a block of marker lines.
/// The markers are emoji, not git's `<<<<<<<`/`=======`/`>>>>>>>`: those are Markdown (a nested
/// blockquote, a setext heading underline), and the editor would render them as such.
enum Merge {
    static let blockMine = "🔽 👤"
    static let blockSeparator = "🔀 ───"
    static let blockTheirs = "🔼 💾"
    static let inlineMine = "👤"
    static let inlineSeparator = "🔀"
    static let inlineTheirs = "💾"

    struct Result: Equatable {
        var text: String
        var conflicts: Int
    }

    /// - Parameters:
    ///   - base: the common ancestor (the file's text when we last read or wrote it).
    ///   - mine: the editor's text.
    ///   - theirs: the file's text now.
    static func merge(base: String, mine: String, theirs: String) -> Result {
        var out: [String] = []
        var conflicts = 0
        for hunk in diff3(base: lines(base), mine: lines(mine), theirs: lines(theirs)) {
            switch hunk {
            case let .resolved(lines):
                out += lines
            case let .conflict(b, m, t):
                if let inline = mergeWords(base: b, mine: m, theirs: t) {
                    out.append(inline.text)
                    conflicts += inline.conflicts
                } else {
                    out.append(blockMine)
                    out += m
                    out.append(blockSeparator)
                    out += t
                    out.append(blockTheirs)
                    conflicts += 1
                }
            }
        }
        return Result(text: out.joined(separator: "\n"), conflicts: conflicts)
    }

    /// The first conflict in `text`: a whole marker block, or one inline conflict.
    static func firstConflict(in text: String) -> NSRange? {
        let ns = text as NSString
        let mine = ns.range(of: inlineMine)
        guard mine.location != NSNotFound else { return nil }
        // The block start line ends with the inline start emoji.
        let blockStart = mine.location - ((blockMine as NSString).length - mine.length)
        let isBlock = blockStart >= 0
            && ns.substring(with: NSRange(location: blockStart, length: (blockMine as NSString).length)) == blockMine
            && (blockStart == 0 || ns.character(at: blockStart - 1) == 0x0A)
        let start = isBlock ? blockStart : mine.location
        let rest = NSRange(location: NSMaxRange(mine), length: ns.length - NSMaxRange(mine))
        let end = ns.range(of: isBlock ? blockTheirs : inlineTheirs, range: rest)
        guard end.location != NSNotFound else { return nil }
        return NSRange(location: start, length: NSMaxRange(end) - start)
    }

    // MARK: - Words

    /// Merge one conflicting line chunk word by word. Nil when a conflict spans a line break
    /// (or a side deleted all its lines): that chunk gets block markers.
    private static func mergeWords(base: [String], mine: [String], theirs: [String]) -> Result? {
        guard !mine.isEmpty, !theirs.isEmpty else { return nil }
        let hunks = diff3(
            base: tokens(base.joined(separator: "\n")),
            mine: tokens(mine.joined(separator: "\n")),
            theirs: tokens(theirs.joined(separator: "\n"))
        )
        var text = ""
        var conflicts = 0
        for hunk in hunks {
            switch hunk {
            case let .resolved(words):
                text += words.joined()
            case let .conflict(_, m, t):
                guard !m.contains("\n"), !t.contains("\n") else { return nil }
                let mineText = m.joined(), theirsText = t.joined()
                text += inlineMine
                if !mineText.isEmpty { text += " " + mineText }
                text += " " + inlineSeparator
                if !theirsText.isEmpty { text += " " + theirsText }
                text += " " + inlineTheirs
                conflicts += 1
            }
        }
        return Result(text: text, conflicts: conflicts)
    }

    /// Words (letters and digits), runs of spaces, line breaks, and single other characters.
    /// Joining the tokens gives back the exact text.
    private static func tokens(_ text: String) -> [String] {
        enum Kind { case word, space, other }
        func kind(_ c: Character) -> Kind {
            if c.isLetter || c.isNumber { return .word }
            if c.isWhitespace && c != "\n" { return .space }
            return .other
        }
        var result: [String] = []
        var current = ""
        var currentKind: Kind?
        for c in text {
            let k = kind(c)
            if k == currentKind, k != .other {
                current.append(c)
            } else {
                if !current.isEmpty { result.append(current) }
                current = String(c)
                currentKind = k
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - diff3

    private enum Hunk<T> {
        case resolved([T])
        case conflict(base: [T], mine: [T], theirs: [T])
    }

    private static func diff3<T: Hashable>(base: [T], mine: [T], theirs: [T]) -> [Hunk<T>] {
        let toMine = matches(base, mine), toTheirs = matches(base, theirs)
        var hunks: [Hunk<T>] = []
        var i = 0, j = 0, k = 0

        while i < base.count || j < mine.count || k < theirs.count {
            // A base element both sides kept in place: copy it.
            if i < base.count, toMine[i] == j, toTheirs[i] == k {
                hunks.append(.resolved([base[i]]))
                i += 1; j += 1; k += 1
                continue
            }
            // The chunk runs to the next base element that both sides kept, or to the end.
            var next = i
            while next < base.count, toMine[next] == nil || toTheirs[next] == nil { next += 1 }
            let endMine = next < base.count ? toMine[next]! : mine.count
            let endTheirs = next < base.count ? toTheirs[next]! : theirs.count
            let b = Array(base[i..<next]), m = Array(mine[j..<endMine]), t = Array(theirs[k..<endTheirs])

            if m == b {
                hunks.append(.resolved(t))
            } else if t == b || m == t {
                hunks.append(.resolved(m))
            } else {
                hunks.append(.conflict(base: b, mine: m, theirs: t))
            }
            i = next; j = endMine; k = endTheirs
        }
        return hunks
    }

    /// Split on "\n" and keep empty lines, so joining with "\n" gives back the exact text.
    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// For each base element, its index in `other` when the shortest diff keeps it, else nil.
    private static func matches<T: Hashable>(_ base: [T], _ other: [T]) -> [Int?] {
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in other.difference(from: base) {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var result = [Int?](repeating: nil, count: base.count)
        var j = 0
        for i in base.indices where !removed.contains(i) {
            while inserted.contains(j) { j += 1 }
            result[i] = j
            j += 1
        }
        return result
    }
}
