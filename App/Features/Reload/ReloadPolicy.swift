import Foundation

/// What to do when the file on disk changes. Pure, so it can be tested without a window.
enum ReloadAction: Equatable {
    case ignore
    case reload
    /// The buffer has unsaved edits: let the user choose.
    case ask
}

enum ReloadPolicy {
    /// - Parameters:
    ///   - disk: the file's text now.
    ///   - buffer: the editor's text.
    ///   - lastKnownDisk: the file's text when we last read or wrote it.
    static func action(disk: String, buffer: String, lastKnownDisk: String) -> ReloadAction {
        if disk == buffer || disk == lastKnownDisk { return .ignore }   // our own save, or a touch
        return buffer == lastKnownDisk ? .reload : .ask
    }
}
