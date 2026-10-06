import Foundation

/// The order of the palette rows. With a query the best fuzzy match leads; with none the recent items lead.
enum PaletteRanking {
    /// `files` come in base order (open files in sidebar order, then closed pins, see `PaletteItems.files`),
    /// `commands` in menu order, `recency` most recent first.
    /// With a query: only matches, by score; equal scores by recency, then base order.
    /// Without, every item scores 0: recent items (files and commands mixed), then the files, then the commands.
    static func rank(files: [PaletteItem], commands: [PaletteItem], query: String, recency: [String]) -> [PaletteItem] {
        var position: [String: Int] = [:]
        for (index, key) in recency.enumerated() where position[key] == nil { position[key] = index }
        let base = files + commands
        let unranked = Int.max
        return base.enumerated()
            .compactMap { index, item in
                score(query, item).map { (item: item, score: $0, recent: position[item.id] ?? unranked, index: index) }
            }
            .sorted { a, b in a.score != b.score ? a.score > b.score : (a.recent, a.index) < (b.recent, b.index) }
            .map(\.item)
    }

    /// The better of the title alone and prefix plus title: "bold" ranks as before, "format" finds all of Format.
    private static func score(_ query: String, _ item: PaletteItem) -> Int? {
        let scores = [FuzzyMatch.score(query, item.title), FuzzyMatch.score(query, "\(item.category) \(item.title)")]
        return scores.compactMap { $0 }.max()
    }
}
