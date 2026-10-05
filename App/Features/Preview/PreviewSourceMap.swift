import Foundation

/// Editor lines → rendered elements. cmark-gfm marks elements with `data-sourcepos="2:1-4:9"`;
/// the lines count from the body, after the front matter.
struct PreviewSourceMap: Equatable {
    struct Block: Equatable {
        /// The attribute value, for finding the element in the page.
        var position: String
        var lines: ClosedRange<Int>
    }

    /// Where to scroll: the element, and how far into it (0 = its top, 1 = its bottom).
    struct Target: Equatable {
        var position: String
        var fraction: Double
    }

    /// In document order. Nested elements follow their parents.
    var blocks: [Block]
    /// Lines of front matter above the body, which the page does not show.
    var frontMatterLines: Int
    /// UTF-16 offsets where the lines of the rendered text (front matter too) start.
    var lineStarts: [Int]

    init(html: String, frontMatterLines: Int = 0, text: String = "") {
        let ns = html as NSString
        blocks = Self.pattern.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let start = Int(ns.substring(with: match.range(at: 2))),
                  let end = Int(ns.substring(with: match.range(at: 3))), start <= end
            else { return nil }
            return Block(position: ns.substring(with: match.range(at: 1)), lines: start...end)
        }
        self.frontMatterLines = frontMatterLines
        var starts = [0]
        for (index, unit) in text.utf16.enumerated() where unit == 0x0A { starts.append(index + 1) }
        lineStarts = starts
    }

    /// The innermost element that contains the 1-based editor `line`. On a line between elements:
    /// the next element, else the last one. Nil for a page without elements.
    func target(forEditorLine line: Int) -> Target? {
        let body = max(line - frontMatterLines, 1)
        // The innermost element starts last; on the same start line, the first (outer) one wins.
        var best: Block?
        for block in blocks where block.lines.contains(body) {
            if best.map({ block.lines.lowerBound > $0.lines.lowerBound }) ?? true { best = block }
        }
        if let best {
            let span = Double(best.lines.count)
            return Target(position: best.position, fraction: Double(body - best.lines.lowerBound) / span)
        }
        guard let next = blocks.first(where: { $0.lines.lowerBound > body }) ?? blocks.last else { return nil }
        return Target(position: next.position, fraction: next.lines.lowerBound > body ? 0 : 1)
    }

    /// 1-based line of the UTF-16 `offset` in the rendered text: the lines that start at or before it.
    func line(atUTF16Offset offset: Int) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return max(low, 1)
    }

    /// Lines the front matter takes: its newlines.
    static func lineCount(of frontMatter: String) -> Int {
        frontMatter.utf16.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
    }

    private static let pattern = try! NSRegularExpression(pattern: #"data-sourcepos="((\d+):\d+-(\d+):\d+)""#)
}
