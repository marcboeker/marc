import AppKit

/// Remembers the size and position of the main window; it opens there again, also after relaunch.
/// AppKit keeps the frame in UserDefaults ("NSWindow Frame DocumentWindow").
@MainActor
final class WindowFrameKeeper {
    private static let name = "DocumentWindow"

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.window = window
        _ = window.setFrameUsingName(Self.name)
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            })
        }
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func save() {
        // Full screen is not a frame to come back to; live resize saves once at its end.
        guard let window, !window.styleMask.contains(.fullScreen), !window.inLiveResize else { return }
        window.saveFrame(usingName: Self.name)
    }
}
