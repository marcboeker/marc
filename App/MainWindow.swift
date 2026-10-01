import AppKit
import SwiftUI

/// Put in the main window's view tree (`.background`). Hands the window to `OpenFiles`, keeps its frame
/// (`WindowFrameKeeper`), and makes its close button (and File > Close in the empty state) close all
/// files first. The window then only hides, so `OpenFiles.showWindow()` can bring it back when a file opens.
struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> AccessorView { AccessorView() }
    func updateNSView(_ nsView: AccessorView, context: Context) {}

    final class AccessorView: NSView {
        private var delegate: MainWindowDelegate?
        private var frameKeeper: WindowFrameKeeper?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, delegate == nil else { return }
            OpenFiles.shared.window = window
            delegate = MainWindowDelegate(window: window)
            frameKeeper = WindowFrameKeeper(window: window)
        }
    }
}

/// Sits in front of SwiftUI's window delegate: answers `windowShouldClose(_:)` and forwards the rest.
@MainActor
private final class MainWindowDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) private let next: NSWindowDelegate?

    init(window: NSWindow) {
        next = window.delegate
        super.init()
        window.delegate = self
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || next?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        next?.responds(to: selector) == true ? next : super.forwardingTarget(for: selector)
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        Task {
            guard await OpenFiles.shared.closeAll() else { return }
            window.orderOut(nil)
        }
        return false
    }
}
