import AppKit
import SwiftUI
import Testing
import MarkdownEngine
@testable import Marc

/// Arrow keys must scroll the caret into view.
@MainActor
struct CaretScrollTests {
    private func makeEditor(text: String) async -> (textView: NSTextView, window: NSWindow)? {
        var config = MarkdownEditorConfiguration()
        config.textInsets = TextInsets(horizontal: 24, vertical: 16)
        guard let editor = await makeTestEditor(text: text, configuration: config) else { return nil }
        editor.window.makeFirstResponder(editor.textView)
        return editor
    }

    private func caretIsVisible(_ textView: NSTextView) -> Bool {
        guard let clip = textView.enclosingScrollView?.contentView else { return false }
        let caret = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        let caretInWindow = textView.window!.convertFromScreen(caret)
        let caretInClip = clip.convert(caretInWindow, from: nil)
        return clip.bounds.contains(NSPoint(x: clip.bounds.midX, y: caretInClip.midY))
    }

    @Test func moveDownScrollsCaretIntoView() async throws {
        let text = (1...200).map { "Line \($0)" }.joined(separator: "\n\n")
        let (textView, window) = try #require(await makeEditor(text: text))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        for _ in 0..<60 {
            textView.moveDown(nil)
            try? await Task.sleep(for: .milliseconds(5))
        }
        let clipY = textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        #expect(clipY > 0, "clip did not scroll")
        #expect(caretIsVisible(textView))
        for _ in 0..<60 {
            textView.moveUp(nil)
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(caretIsVisible(textView))
        withExtendedLifetime(window) {}
    }

    /// Distance between the clip origin and the lowest origin the scroller allows.
    private func distanceFromScrollEnd(_ textView: NSTextView) -> CGFloat {
        guard let scrollView = textView.enclosingScrollView,
              let doc = scrollView.documentView else { return .infinity }
        let clip = scrollView.contentView
        return doc.frame.height - clip.bounds.height - clip.bounds.origin.y
    }

    /// The last row reveals like any other row: the caret comes into view, and the
    /// overscroll slack below it stays unscrolled until the reader scrolls there.
    @Test func caretOnLastRowRevealsWithoutScrollingToEnd() async throws {
        let text = (1...200).map { "Line \($0)" }.joined(separator: "\n\n")
        let (textView, window) = try #require(await makeEditor(text: text))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.moveToEndOfDocument(nil)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(caretIsVisible(textView))
        #expect(distanceFromScrollEnd(textView) > 1)
        withExtendedLifetime(window) {}
    }

    @Test func typingNewLinesAtEndKeepsCaretVisible() async throws {
        let text = (1...200).map { "Line \($0)" }.joined(separator: "\n\n")
        let (textView, window) = try #require(await makeEditor(text: text))
        textView.moveToEndOfDocument(nil)
        for _ in 0..<5 {
            textView.insertNewline(nil)
            try? await Task.sleep(for: .milliseconds(20))
            #expect(caretIsVisible(textView))
            #expect(distanceFromScrollEnd(textView) > 1)
        }
        withExtendedLifetime(window) {}
    }

    @Test func caretAboveLastRowDoesNotScrollToEnd() async throws {
        let text = (1...200).map { "Line \($0)" }.joined(separator: "\n\n")
        let (textView, window) = try #require(await makeEditor(text: text))
        textView.moveToEndOfDocument(nil)
        textView.moveUp(nil)
        textView.moveUp(nil)
        let clip = try #require(textView.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y - 100))
        let before = clip.bounds.origin.y
        textView.moveUp(nil)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(clip.bounds.origin.y == before)
        withExtendedLifetime(window) {}
    }
}

