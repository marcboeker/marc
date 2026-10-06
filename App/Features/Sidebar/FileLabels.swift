import Foundation

/// Sidebar row labels: the file name without extension. When two open files have the same name,
/// each also gets as many of its parent folders as make it unique ("notes", "work/notes").
enum FileLabels {
    struct Label: Equatable {
        let name: String
        /// Parent folders, only for names that collide. Nil for untitled files.
        let folder: String?
    }

    /// One label per file, in the same order. `url` nil = untitled, shown as `displayName`.
    static func labels(for files: [(url: URL?, displayName: String)]) -> [Label] {
        let names = files.map { $0.url?.deletingPathExtension().lastPathComponent ?? $0.displayName }
        // Parent folders, nearest first.
        let parents = files.map { $0.url.map { Array($0.deletingLastPathComponent().pathComponents.filter { $0 != "/" }.reversed()) } ?? [] }
        return files.indices.map { i in
            let others = files.indices.filter { $0 != i && names[$0].lowercased() == names[i].lowercased() }
            guard !others.isEmpty, files[i].url != nil else { return Label(name: names[i], folder: nil) }
            // The fewest folders that tell it from the rest; if none do (/a vs /b/a), the full path.
            let folder = parents[i].indices.map { path(parents[i], $0 + 1) }
                .first { f in others.allSatisfy { path(parents[$0], f.split(separator: "/").count) != f } }
            return Label(name: names[i], folder: folder ?? "/" + path(parents[i], parents[i].count))
        }
    }

    /// The `depth` nearest folders, outermost first: "work/notes".
    private static func path(_ parents: [String], _ depth: Int) -> String {
        parents.prefix(depth).reversed().joined(separator: "/")
    }
}
