import AppKit
import SwiftUI
import MarkdownEngine

/// Hosts the engine editor in an unshown window and waits for `onTextViewReady`.
/// The caller must keep the window alive for the test's duration.
@MainActor
func makeTestEditor(
    text: String = "hello",
    configuration: MarkdownEditorConfiguration = .default,
    onSaveRequest: @escaping (NSTextView) -> Bool = { _ in false },
    onWillPaste: @escaping (NSTextView, NSPasteboard) -> Bool = { _, _ in false }
) async -> (textView: NSTextView, window: NSWindow)? {
    var ready: NSTextView?
    let editor = NativeTextViewWrapper(
        text: .constant(text),
        configuration: configuration,
        onTextViewReady: { ready = $0 },
        onWillPaste: onWillPaste,
        onSaveRequest: onSaveRequest
    )
    let host = NSHostingView(rootView: editor)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    for _ in 0..<50 where ready == nil { try? await Task.sleep(for: .milliseconds(20)) }
    guard let ready else { return nil }
    return (ready, window)
}
