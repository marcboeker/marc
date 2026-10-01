import AppKit
import SwiftUI
import Testing
import MarkdownEngine

/// One engine editor, two documents with their own text bindings, switched the way ContentView does.
@MainActor
struct EditorSwitchTests {
    private final class Texts {
        var values = ["a": "alpha", "b": "beta"]
    }

    private let texts = Texts()

    private func editor(
        _ id: String, ready: @escaping (NSTextView) -> Void = { _ in }, shown: @escaping (String) -> Void = { _ in }
    ) -> NativeTextViewWrapper {
        NativeTextViewWrapper(
            text: Binding(get: { texts.values[id]! }, set: { texts.values[id] = $0 }),
            documentId: id,
            onTextViewReady: ready,
            onDocumentShown: shown
        )
    }

    /// Shows document "a", types "!" at its end, and switches to "b" before the engine's push lands.
    private func typeThenSwitch() async throws -> (NSTextView, NSHostingView<NativeTextViewWrapper>, NSWindow) {
        var ready: NSTextView?
        let host = NSHostingView(rootView: editor("a") { ready = $0 })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        for _ in 0..<50 where ready == nil { try await Task.sleep(for: .milliseconds(20)) }
        let textView = try #require(ready)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText("!", replacementRange: textView.selectedRange())
        host.rootView = editor("b")
        host.layoutSubtreeIfNeeded()
        return (textView, host, window)
    }

    @Test func editQueuedBeforeASwitchLandsInItsOwnDocument() async throws {
        let (textView, _, window) = try await typeThenSwitch()
        defer { withExtendedLifetime(window) {} }
        #expect(textView.string == "beta")
        try await Task.sleep(for: .milliseconds(100))
        #expect(texts.values == ["a": "alpha!", "b": "beta"])

        // Edits in the new document go to its own binding.
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertText("?", replacementRange: textView.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        #expect(texts.values == ["a": "alpha!", "b": "beta?"])
    }

    /// The late push must not look like an outside rewrite: undo of "a" survives the round trip.
    @Test func undoSurvivesASwitchRightAfterTyping() async throws {
        let (textView, host, window) = try await typeThenSwitch()
        defer { withExtendedLifetime(window) {} }
        try await Task.sleep(for: .milliseconds(100))
        host.rootView = editor("a")
        host.layoutSubtreeIfNeeded()
        #expect(textView.string == "alpha!")
        #expect(textView.undoManager?.canUndo == true)
    }

    /// A document rewritten while switched away drops its undo stack.
    @Test func undoIsDroppedWhenTheTextChangedWhileAway() async throws {
        let (textView, host, window) = try await typeThenSwitch()
        defer { withExtendedLifetime(window) {} }
        try await Task.sleep(for: .milliseconds(100))
        texts.values["a"] = "rewritten on disk"
        host.rootView = editor("a")
        host.layoutSubtreeIfNeeded()
        #expect(textView.string == "rewritten on disk")
        #expect(textView.undoManager?.canUndo == false)
    }

    /// Each document keeps its selection across a switch, and the embedder hears when a document is shown.
    @Test func selectionComesBackAfterASwitch() async throws {
        let (textView, host, window) = try await typeThenSwitch()
        defer { withExtendedLifetime(window) {} }
        textView.setSelectedRange(NSRange(location: 1, length: 2))   // in "b"
        try await Task.sleep(for: .milliseconds(100))
        var shown: [String] = []
        host.rootView = editor("a", shown: { shown.append($0) })
        host.layoutSubtreeIfNeeded()
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))   // after the typed "!"
        host.rootView = editor("b", shown: { shown.append($0) })
        host.layoutSubtreeIfNeeded()
        #expect(textView.selectedRange() == NSRange(location: 1, length: 2))
        try await Task.sleep(for: .milliseconds(50))
        #expect(shown == ["a", "b"])
    }
}
