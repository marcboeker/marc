import Foundation
import Markdown

struct LintIssue: Equatable, Sendable {
    /// 1-based line in the full file (front matter included).
    let line: Int
    let message: String
}

/// Pure lint rules: broken relative link/image targets and heading level jumps.
/// YAML front matter is skipped; line numbers stay relative to the full file.
func lint(_ text: String, documentFolder: URL?) -> [LintIssue] {
    var walker = LintWalker(documentFolder: documentFolder)
    walker.visit(Document(parsing: blankingFrontMatter(in: text), options: .disableSmartOpts))
    return walker.issues
}

/// Replaces front matter lines with empty lines so line numbers are unchanged.
func blankingFrontMatter(in text: String) -> String {
    let parts = FrontMatterSplit.split(text)
    let newlines = parts.front.unicodeScalars.filter { $0 == "\n" }.count
    return String(repeating: "\n", count: newlines) + parts.body
}

private struct LintWalker: MarkupWalker {
    let documentFolder: URL?
    var issues: [LintIssue] = []
    private var previousLevel: Int?

    init(documentFolder: URL?) {
        self.documentFolder = documentFolder
    }

    mutating func visitHeading(_ heading: Heading) {
        if let previous = previousLevel, heading.level > previous + 1, let line = heading.range?.lowerBound.line {
            issues.append(LintIssue(line: line, message: "Heading level jumps from H\(previous) to H\(heading.level)."))
        }
        previousLevel = heading.level
        descendInto(heading)
    }

    mutating func visitLink(_ link: Link) {
        check(link.destination, at: link.range)
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        check(image.source, at: image.range)
        descendInto(image)
    }

    private mutating func check(_ destination: String?, at range: SourceRange?) {
        guard let destination, let line = range?.lowerBound.line,
              let url = Self.fileURL(for: destination, folder: documentFolder) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            issues.append(LintIssue(line: line, message: "File not found: \(destination)"))
        }
    }

    /// File to check, or nil when the target is not a local file (or cannot be checked).
    static func fileURL(for destination: String, folder: URL?) -> URL? {
        var target = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
        if let cut = target.firstIndex(where: { $0 == "#" || $0 == "?" }) { target = String(target[..<cut]) }
        guard !target.isEmpty, !target.hasPrefix("//") else { return nil }
        let decoded = target.removingPercentEncoding ?? target
        if decoded.lowercased().hasPrefix("file:") {
            return URL(string: target).flatMap { $0.isFileURL ? $0 : nil }
        }
        if decoded.prefixMatch(of: /[A-Za-z][A-Za-z0-9+.-]*:/) != nil { return nil }
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        guard let folder else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: folder)
    }
}
