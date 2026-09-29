import Foundation
import Markdown

struct OutlineItem: Identifiable, Equatable {
    let level: Int
    let title: String
    /// UTF-16 range of the heading (ATX line or setext lines) in the full text.
    let range: NSRange

    var id: Int { range.location }
}

/// Headings of a Markdown document, in order. Front matter is skipped; offsets stay relative to `text`.
func outline(of text: String) -> [OutlineItem] {
    let parts = FrontMatterSplit.split(text)
    let body = parts.body
    let base = parts.front.utf16.count
    let utf8 = body.utf8

    // UTF-8 byte offset of each line start (1-based line numbers map to index line - 1).
    var lineStarts = [0]
    for (offset, byte) in utf8.enumerated() where byte == UInt8(ascii: "\n") {
        lineStarts.append(offset + 1)
    }

    func utf16Offset(_ location: SourceLocation) -> Int? {
        guard location.line >= 1, location.line <= lineStarts.count else { return nil }
        let byte = lineStarts[location.line - 1] + location.column - 1
        guard byte <= utf8.count else { return nil }
        let index = utf8.index(utf8.startIndex, offsetBy: byte)
        return base + body.utf16.distance(from: body.startIndex, to: index)
    }

    var collector = HeadingCollector()
    collector.visit(Document(parsing: body, options: .disableSmartOpts))
    return collector.headings.compactMap { heading in
        guard let range = heading.range,
              let start = utf16Offset(range.lowerBound),
              let end = utf16Offset(range.upperBound) else { return nil }
        return OutlineItem(
            level: heading.level,
            title: plainTitle(heading),
            range: NSRange(location: start, length: end - start)
        )
    }
}

private struct HeadingCollector: MarkupWalker {
    var headings: [Heading] = []

    mutating func visitHeading(_ heading: Heading) {
        headings.append(heading)
    }
}

private func plainTitle(_ markup: Markup) -> String {
    var result = ""
    for child in markup.children {
        switch child {
        case let text as Text: result += text.string
        case let code as InlineCode: result += code.code
        case is SoftBreak, is LineBreak: result += " "
        case is InlineHTML: break
        default: result += plainTitle(child)
        }
    }
    return result.trimmingCharacters(in: .whitespaces)
}
