//  Marc: resolves `![alt](path)` image destinations to files. Relative paths
//  resolve against `baseURL` (the folder of the .md file). Assign it with
//  `configuration.services.images = FileImageProvider(baseURL: folder)`.

import AppKit
import Foundation

public struct FileImageProvider: EmbeddedImageProvider {
    public var baseURL: URL?

    public init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    public func image(for reference: EmbeddedImageRequest) -> NSImage? {
        guard let url = Self.resolve(reference.name, baseURL: baseURL) else { return nil }
        return Self.cachedImage(at: url)
    }

    public func fingerprint() -> AnyHashable { baseURL }

    /// File URL for a Markdown image destination, or nil for remote / unresolvable ones.
    /// Handles `<a b.png>`, a trailing `"title"`, percent-escapes, `file:` URLs,
    /// absolute paths, and paths relative to `baseURL`.
    public static func resolve(_ destination: String, baseURL: URL?) -> URL? {
        var dest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if dest.hasPrefix("<"), let close = dest.firstIndex(of: ">") {
            dest = String(dest[dest.index(after: dest.startIndex)..<close])
        } else if let space = dest.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            dest = String(dest[..<space])
        }
        guard !dest.isEmpty else { return nil }
        let decoded = dest.removingPercentEncoding ?? dest
        if decoded.hasPrefix("file:") { return URL(string: dest).flatMap { $0.isFileURL ? $0 : nil } }
        if decoded.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil { return nil }
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }
        guard let baseURL else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()).standardizedFileURL
    }

    // Keyed by path; the modification date invalidates an entry when the file changes.
    private static let cache = NSCache<NSString, CachedImage>()

    private final class CachedImage {
        let image: NSImage
        let modified: Date
        init(image: NSImage, modified: Date) { self.image = image; self.modified = modified }
    }

    private static func cachedImage(at url: URL) -> NSImage? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        let modified = values.contentModificationDate ?? .distantPast
        let key = url.path as NSString
        if let hit = cache.object(forKey: key), hit.modified == modified { return hit.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(CachedImage(image: image, modified: modified), forKey: key)
        return image
    }
}
