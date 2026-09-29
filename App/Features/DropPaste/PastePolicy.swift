import Foundation

/// Decides whether HTML on the pasteboard is worth converting.
enum PastePolicy {
    /// True when the HTML adds nothing over the plain text flavor.
    ///
    /// Sources such as Terminal or code editors put styled HTML (spans, divs, breaks
    /// for colors and fonts) next to the plain text. Converting that only mangles
    /// whitespace. The rule: the HTML has no semantic tag (links, emphasis, headings,
    /// lists, code, images, tables, quotes) AND its visible text equals the plain text
    /// after whitespace is collapsed. Bold text from a web page has a semantic tag,
    /// so it still converts.
    static func prefersPlainText(html: String, plain: String?) -> Bool {
        guard let plain, !plain.isEmpty else { return false }
        guard !hasSemanticTag(html) else { return false }
        return collapse(visibleText(html)) == collapse(plain)
    }

    private static func hasSemanticTag(_ html: String) -> Bool {
        html.contains(/(?i)<(a|b|strong|i|em|u|s|del|strike|h[1-6]|ul|ol|li|pre|code|img|table|blockquote|hr)[\s>\/]/)
    }

    static func visibleText(_ html: String) -> String {
        var text = html.replacing(/(?is)<(head|style|script)\b.*?<\/\1>/, with: "")
        text = text.replacing(/(?i)<br\s*\/?>/, with: " ")
        text = text.replacing(/<[^>]*>/, with: "")
        return decodeEntities(text)
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s.replacing(/&#(x?)([0-9a-fA-F]+);/) { match in
            let radix = match.1.isEmpty ? 10 : 16
            guard let value = UInt32(match.2, radix: radix), let scalar = Unicode.Scalar(value) else {
                return String(match.0)
            }
            return String(Character(scalar))
        }
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
