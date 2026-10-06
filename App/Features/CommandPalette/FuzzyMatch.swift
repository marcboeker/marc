import Foundation

/// How well a typed query fits a palette title. The query letters must appear in order (a subsequence),
/// ignoring case and spaces. Letters at word starts and runs of letters score more, so "tl" finds
/// "Task List", and a prefix beats word starts, which beat letters scattered inside words.
enum FuzzyMatch {
    private static let matched = 1
    private static let wordStart = 10
    private static let textStart = 5
    private static let consecutive = 6

    /// Nil when the query is not a subsequence of the text. An empty query scores 0.
    static func score(_ query: String, _ text: String) -> Int? {
        let query = query.filter { !$0.isWhitespace }.map { $0.lowercased() }
        let original = Array(text)
        let text = original.map { $0.lowercased() }
        guard !query.isEmpty else { return 0 }
        guard query.count <= text.count else { return nil }
        // best[j]: the best score with the current query letter matched at text index j.
        var best = [Int?](repeating: nil, count: text.count)
        for (i, letter) in query.enumerated() {
            var next = [Int?](repeating: nil, count: text.count)
            for j in i..<text.count where text[j] == letter {
                let here = matched + bonus(original, j)
                if i == 0 {
                    next[j] = here
                    continue
                }
                // The previous letter at k < j: a run continues at k = j - 1, a gap costs one per skipped letter.
                next[j] = (i - 1..<j).compactMap { k in
                    best[k].map { $0 + here + (k == j - 1 ? consecutive : -(j - k - 1)) }
                }.max()
            }
            best = next
        }
        // Shorter titles win a tie: "prv" ranks "Preview" above "Previous File".
        return best.compactMap { $0 }.max().map { $0 - (text.count - query.count) / 4 }
    }

    /// A letter at the start of the text or a word (after a space or punctuation, or a camel-case hump).
    private static func bonus(_ text: [Character], _ index: Int) -> Int {
        guard index > 0 else { return wordStart + textStart }
        let previous = text[index - 1], current = text[index]
        let startsWord = !(previous.isLetter || previous.isNumber) || (previous.isLowercase && current.isUppercase)
        return startsWord ? wordStart : 0
    }
}
