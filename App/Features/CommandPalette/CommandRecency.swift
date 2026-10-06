import AppKit

/// The palette items the user ran last, most recent first, as recency keys (`PaletteItem.id`). They stay
/// across launches and put the usual commands and files on top of the palette.
@MainActor
final class CommandRecency {
    static let shared = CommandRecency()

    private(set) var keys: [String]

    private static let key = "commandRecency"
    private let defaults: UserDefaults
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 50) {
        self.defaults = defaults
        self.limit = limit
        keys = defaults.stringArray(forKey: Self.key) ?? []
    }

    /// Move the key to the front, or add it there. The oldest keys fall off past `limit`.
    func record(_ recent: String) {
        keys = Array(([recent] + keys.filter { $0 != recent }).prefix(limit))
        defaults.set(keys, forKey: Self.key)
    }

    /// Count every menu command: clicks, shortcuts and launcher runs all post `didSendActionNotification`.
    /// Synchronous (no queue): SwiftUI may replace the item soon after, and the key needs its menu. Call once.
    func observeMenus() {
        NotificationCenter.default.addObserver(forName: NSMenu.didSendActionNotification, object: nil, queue: nil) { note in
            // Posted on the main thread, where the item lives.
            nonisolated(unsafe) let item = note.userInfo?["MenuItem"] as? NSMenuItem
            MainActor.assumeIsolated {
                if let item, let key = PaletteItems.recencyKey(for: item) { self.record(key) }
            }
        }
    }
}
