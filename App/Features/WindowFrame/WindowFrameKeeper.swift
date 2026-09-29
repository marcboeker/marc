import AppKit
import SwiftUI

/// Remembers the size and position of the last moved or resized document window.
/// A new window opens there (cascaded when another window is already at that place).
/// AppKit keeps the frame in UserDefaults ("NSWindow Frame DocumentWindow").
@MainActor
final class WindowFrameKeeper {
    private static let name = "DocumentWindow"
    /// Offset for a window that would cover another window exactly.
    private static let cascade: CGFloat = 22

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.window = window
        restore(window)
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

    private func restore(_ window: NSWindow) {
        // A new tab takes the frame of its tab group.
        guard (window.tabbedWindows?.count ?? 1) <= 1, window.setFrameUsingName(Self.name) else { return }
        let others = NSApp.windows.filter { $0 !== window && $0.isVisible }
        var frame = window.frame
        for _ in 0..<20 where others.contains(where: { $0.frame.origin == frame.origin }) {
            frame.origin.x += Self.cascade
            frame.origin.y -= Self.cascade
        }
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: false)
    }

    private func save() {
        // Full screen is not a frame to come back to; live resize saves once at its end.
        guard let window, !window.styleMask.contains(.fullScreen), !window.inLiveResize else { return }
        window.saveFrame(usingName: Self.name)
    }
}

/// Put in a document window's view tree (`.background`); starts a `WindowFrameKeeper`
/// for the window it lands in.
struct WindowFrameRestorer: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowFrameView { WindowFrameView() }
    func updateNSView(_ nsView: WindowFrameView, context: Context) {}

    final class WindowFrameView: NSView {
        private var keeper: WindowFrameKeeper?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if keeper == nil, let window { keeper = WindowFrameKeeper(window: window) }
        }
    }
}
