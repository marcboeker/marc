import Foundation

/// One pinned file. The bookmark follows the file when it is renamed or moved; `url` is where it was last seen.
struct Pin: Identifiable, Equatable, Codable {
    let id: UUID
    var bookmark: Data
    var url: URL

    /// The name in the sidebar and in messages: the file name without extension.
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// A pin whose file was gone when it was activated. Each notice gets a new id, so a second one restarts the timer.
struct MissingPinNotice: Equatable, Identifiable {
    let id = UUID()
    let message: String

    init(_ pin: Pin) {
        message = "“\(pin.name)” was not found. Its pin is removed."
    }
}

/// The pinned files, in the order they were pinned. They stay across launches and when the file is closed.
/// A pin is removed by the user, or when the user activates it and the file is gone (`resolve`).
@MainActor
@Observable
final class Pins {
    static let shared = Pins()

    private(set) var items: [Pin] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pinnedFiles") {
        self.defaults = defaults
        self.key = key
        // No disk check here: a pin whose file is gone stays until the user activates it.
        if let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode([Pin].self, from: data) {
            items = stored
        }
    }

    /// The same file gives the same key, also through symlinks (`/var` and `/private/var`).
    static func key(_ url: URL) -> URL {
        url.resolvedFileURL
    }

    func pin(for url: URL) -> Pin? {
        let key = Self.key(url)
        return items.first { Self.key($0.url) == key }
    }

    func isPinned(_ url: URL?) -> Bool {
        url.map { pin(for: $0) != nil } ?? false
    }

    /// Pin the file at the end of the list. Nothing happens when it cannot be pinned: no file (untitled),
    /// no bookmark possible, or already pinned.
    func pin(_ url: URL?) {
        guard let url, !isPinned(url), let bookmark = try? url.bookmarkData() else { return }
        items.append(Pin(id: UUID(), bookmark: bookmark, url: url.standardizedFileURL))
        save()
    }

    func unpin(_ pin: Pin) {
        items.removeAll { $0.id == pin.id }
        save()
    }

    /// Where the pinned file is now, or nil when it is gone. In that case the pin is removed.
    /// Follows renames and moves, and renews a stale bookmark.
    func resolve(_ pin: Pin) -> URL? {
        guard let index = items.firstIndex(where: { $0.id == pin.id }) else { return nil }
        guard let (url, stale) = Self.resolve(items[index].bookmark), FileManager.default.fileExists(atPath: url.path),
              !Self.isInTrash(url) else {
            unpin(pin)
            return nil
        }
        update(index, url: url, renew: stale)
        return url
    }

    /// An open file got a new URL (Save As, Move To, rename). A pin on the old URL follows when its bookmark
    /// says the file itself moved. With Save As the old file stays where it is, and so does the pin.
    func fileMoved(from old: URL?, to new: URL?) {
        guard let old, let new, old != new else { return }
        let oldKey = Self.key(old)
        guard let index = items.firstIndex(where: { Self.key($0.url) == oldKey }),
              let (url, stale) = Self.resolve(items[index].bookmark), Self.key(url) == Self.key(new) else { return }
        update(index, url: new, renew: stale)
    }

    /// A bookmark follows a file into the Trash; for the user that file is gone.
    private static func isInTrash(_ url: URL) -> Bool {
        guard let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
        else { return false }
        let root = trash.resolvedFileURL.path(percentEncoded: false)
        return url.resolvedFileURL.path(percentEncoded: false).hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func resolve(_ bookmark: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale) else {
            return nil
        }
        return (url.standardizedFileURL, stale)
    }

    private func update(_ index: Int, url: URL, renew: Bool) {
        var pin = items[index]
        if renew, let bookmark = try? url.bookmarkData() { pin.bookmark = bookmark }
        pin.url = url
        guard pin != items[index] else { return }
        items[index] = pin
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(items), forKey: key)
    }
}
