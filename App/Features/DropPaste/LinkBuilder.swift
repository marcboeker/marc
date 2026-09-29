import Foundation
import UniformTypeIdentifiers

/// Pure builder for the Markdown inserted when files are dropped on the editor.
enum LinkBuilder {
    /// One Markdown link per file, one per line.
    static func markdown(for files: [URL], documentFolder: URL?) -> String {
        files.map { link(for: $0, documentFolder: documentFolder) }.joined(separator: "\n")
    }

    static func link(for file: URL, documentFolder: URL?) -> String {
        let path = destination(for: file, documentFolder: documentFolder)
        let target = needsBrackets(path) ? "<\(escapeAngles(path))>" : path
        if isImage(file) {
            let name = file.deletingPathExtension().lastPathComponent
            return "![\(escapeBrackets(name))](\(target))"
        }
        return "[\(escapeBrackets(file.lastPathComponent))](\(target))"
    }

    /// Path relative to `documentFolder`, or absolute when there is no folder, the
    /// volumes differ, or the two paths share nothing but the root.
    static func destination(for file: URL, documentFolder: URL?) -> String {
        let file = file.standardizedFileURL
        guard let folder = documentFolder?.standardizedFileURL, sameVolume(file, folder) else {
            return file.path
        }
        let target = file.pathComponents
        let base = folder.pathComponents
        var common = 0
        while common < min(target.count, base.count), target[common] == base[common] { common += 1 }
        guard common > 1 else { return file.path }
        let parts = Array(repeating: "..", count: base.count - common) + target[common...]
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let x = try? a.resourceValues(forKeys: keys).volumeIdentifier as? NSObject,
              let y = try? b.resourceValues(forKeys: keys).volumeIdentifier as? NSObject
        else { return true }  // a path that does not exist yet: assume the same volume
        return x.isEqual(y)
    }

    private static func needsBrackets(_ path: String) -> Bool {
        path.contains { " ()<>".contains($0) }
    }

    private static func escapeAngles(_ s: String) -> String {
        s.replacingOccurrences(of: "<", with: "\\<").replacingOccurrences(of: ">", with: "\\>")
    }

    private static func escapeBrackets(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
