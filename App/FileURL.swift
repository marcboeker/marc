import Foundation
import UniformTypeIdentifiers

extension URL {
    /// The same file gives the same URL, also through `..` and symlinks (`/var` and `/private/var`).
    var resolvedFileURL: URL {
        standardizedFileURL.resolvingSymlinksInPath()
    }

    /// A Markdown file by its extension: `.md`, or a type that conforms to Markdown (`.markdown`, `.mdown` …).
    var isMarkdownFile: Bool {
        guard isFileURL else { return false }
        if pathExtension.lowercased() == "md" { return true }
        return UTType(filenameExtension: pathExtension)?.conforms(to: .markdown) ?? false
    }
}
