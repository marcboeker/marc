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
        let parents = files.map { file in
            file.url.map { Array($0.deletingLastPathComponent().pathComponents.filter { $0 != "/" }.reversed()) } ?? []
        }
        return files.indices.map { index in
            let name = names[index]
            let others = files.indices.filter { $0 != index && names[$0].lowercased() == name.lowercased() }
            guard !others.isEmpty, files[index].url != nil else { return Label(name: name, folder: nil) }
            for depth in parents[index].indices.map({ $0 + 1 }) {
                let folder = path(parents[index], depth)
                if others.allSatisfy({ path(parents[$0], depth) != folder }) { return Label(name: name, folder: folder) }
            }
            // All its folders are the end of another file's folders (/a vs /b/a): the full path.
            return Label(name: name, folder: "/" + path(parents[index], parents[index].count))
        }
    }

    /// The `depth` nearest folders, outermost first: "work/notes".
    private static func path(_ parents: [String], _ depth: Int) -> String {
        parents.prefix(depth).reversed().joined(separator: "/")
    }
}
