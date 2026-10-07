import AppKit
import SwiftUI
import Testing
import MarkdownEngine
@testable import Marcdown

/// Checks the engine fork's hooks through a real (offscreen) editor.
@MainActor
struct EngineHookTests {
    @Test func textViewReadyDeliversRawMarkdown() async {
        let editor = await makeTestEditor(text: "# Title\n\n[[not a wiki link]]")
        #expect(editor?.textView.string == "# Title\n\n[[not a wiki link]]")
    }

    @Test func saveActionReachesHook() async {
        var called = false
        let editor = await makeTestEditor(onSaveRequest: { _ in called = true; return true })
        _ = editor?.textView.tryToPerform(#selector(NSDocument.save(_:)), with: nil)
        #expect(called)
    }

    @Test func findShowsFindBar() async throws {
        let (textView, window) = try #require(await makeTestEditor())
        defer { withExtendedLifetime(window) {} }
        let controller = EditorController()
        controller.attach(textView)
        #expect(textView.enclosingScrollView?.isFindBarVisible == false)
        controller.performFind(.showFindInterface)
        #expect(textView.enclosingScrollView?.isFindBarVisible == true)
    }

    @Test func pasteHookRunsAndCanHandle() async {
        var called = false
        let editor = await makeTestEditor(onWillPaste: { _, _ in called = true; return true })
        editor?.textView.paste(nil)
        #expect(called)
        #expect(editor?.textView.string == "hello")
    }
}
