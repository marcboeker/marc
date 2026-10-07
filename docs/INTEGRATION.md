# Integration guide for feature agents

Phase 1 wired everything shared. Each feature edits ONLY its own folder and its own test file.

| Feature | Folder | Test file (you create it) |
|---|---|---|
| Formatting | `App/Features/Formatting/` | `Tests/FormattingTests.swift` |
| Lint | `App/Features/Lint/` | `Tests/LintTests.swift` |
| Outline | `App/Features/Outline/` | `Tests/OutlineTests.swift` |
| Shortcuts | `App/Features/Shortcuts/` | `Tests/ShortcutsTests.swift` |
| DropPaste | `App/Features/DropPaste/` | `Tests/DropPasteTests.swift` |

Do not touch: `Marcdown.xcodeproj`, `Packages/`, `App/*.swift`, other features' folders, `Makefile`.
`App/` and `Tests/` are synchronized folders: new `.swift` files are picked up without project edits
(verified). If you need a shared change, stop and report it instead of editing.

## Build and test

```
make build DERIVED=.build/dd-<feature>
make test  DERIVED=.build/dd-<feature>     # prints only results, failures, errors
```
Always use a private `DERIVED` path when agents run in parallel. Tests use Swift Testing
(`import Testing`, `@testable import Marcdown`) and run hosted inside the app. `import Markdown`
(swift-markdown) works in tests. Test only pure logic. Do not open windows in tests
(`Tests/EngineHookTests.swift` shows an offscreen editor if you really need one).

## Shell (do not edit, use it)

`App/EditorController.swift`: `@MainActor @Observable final class EditorController`, one per window.
```swift
weak var textView: NSTextView?          // nil until ready (a run-loop tick after the window opens)
var fileURL: URL?                       // nil = unsaved; changes after Save As
var text: String                        // observable mirror of the document binding (trails edits by one tick)
var currentText: String                 // exact editor text (textView.string); use this in logic
var documentFolder: URL?                // fileURL's folder, nil if unsaved
var selectedRange: NSRange
private(set) var textViewGeneration: Int   // bumped when the text view is attached
let lint: LintController                // lazy, owned here
let dropPaste: DropPasteHandler         // lazy, owned here
func replaceAll(with: String, selection: NSRange? = nil)   // ONE undo step, keeps/clamps selection
func setSelectedRange(_ range: NSRange, scroll: Bool = true) // clamps, scrolls, focuses the text view
```
Menu commands reach the key window's controller with
`@FocusedValue(\.editorController) private var controller`.

Undo-safe edits: `replaceAll` does `shouldChangeText` / `textStorage.replaceCharacters` / `didChangeText`, so
Cmd-Z restores, the engine restyles, and the document binding is updated. For partial edits do the same
yourself on `textView` with the affected range (never assign `textView.string`, never write to `textStorage`
without shouldChangeText/didChangeText). Note the binding update is asynchronous (next run-loop turn).
To preserve line/column on format: compute the old line and column from `selectedRange` and
`currentText`, compute the new UTF-16 location, pass it as `selection:`.

## Feature entry points (stubs you replace)

- Formatting: `MarkdownFormatting.format(_ text: String) -> String` (pure, test this) and
  `extension EditorController { func formatForSave() }` in `EditorController+Formatting.swift`. Called on explicit
  save only. Flow: File > Save or Cmd-S with the editor focused -> engine hook `onSaveRequest` ->
  `EditorController.saveRequested()` -> `formatForSave()` -> next run-loop turn `NSDocument.save`.
  Autosave and Save As never call it. Keep `formatForSave` synchronous.
- Lint: `LintController` (`init(controller:)`, `install(on:)` called when the text view is ready, debounced
  `lint(text:)`, `var debounce`). Text changes come from `NSText.didChangeNotification`. Gutter icons: draw
  your own overlay view added to the text view / its scroll view; keep it in your folder.
- Outline: `OutlineView(controller:)` is the sidebar. Observe `controller.text` (re-renders on edits).
  Jump with `controller.setSelectedRange(_, scroll: true)`.
- Shortcuts: `FormatCommands: Commands` (added to the scene). Use `@FocusedValue(\.editorController)`. Menu
  key equivalents are handled before the text view sees keys. Stack of edits: use the undo-safe rules above.
- DropPaste: `DropPasteHandler.willPaste(in:pasteboard:) -> Bool` and `drop(in:info:insertionIndex:) -> Bool`.
  `true` = handled, `false` = engine default. `controller` gives `documentFolder` / `fileURL` for relative paths.

## Engine hooks (fork, see `Packages/MarkdownEngine/NOTICE`)

- `onTextViewReady: (NSTextView) -> Void`. Async on the main queue, once. Feeds `EditorController.attach`.
- `onWillPaste: (NSTextView, NSPasteboard) -> Bool`. Called at the start of `paste(_:)` (Cmd-V, Edit > Paste).
  Not called for Option-Shift-Cmd-V (`pasteAsPlainText:`), which the fork overrides to insert the
  plain-text flavor verbatim (no HTML conversion). Demark is async: return `true`, then insert later on the main
  actor; re-check that the selection is still sensible.
- `onDropFiles: (NSTextView, NSDraggingInfo, Int) -> Bool`. Only for file URL drops. The Int is the UTF-16
  insertion index from `characterIndexForInsertion`. Read URLs with
  `info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`.
  Insert with the undo-safe pattern (shouldChangeText/replaceCharacters/didChangeText, range at the index).
- `onSaveRequest: (NSTextView) -> Bool` (`saveDocument:`), wired to `saveRequested()`.
- Images: `FileImageProvider(baseURL:)` set in `ContentView.configuration`. `![a](rel/x.png)` renders inline
  only when the image is the only thing in its paragraph. `FileImageProvider.resolve(_:baseURL:)` is public and
  pure (handles `<a b.png>`, titles, percent escapes); reuse it for lint (broken image target).
  It only sees the destination string, so lint must do its own file check for links.

## Engine facts that matter

- **The text view string is raw Markdown.** Syntax characters stay in `textStorage`; the live preview only styles
  them (inactive markers get font size 0.1 pt and shrink, code-span markers get alpha). Ranges are UTF-16
  `NSRange` into `textView.string`, the same as `NSString`. So `currentText` maps 1:1 to the file. The only
  upstream transform (wiki-link `|id` storage/display split) is off (`MarkdownEngineFeatures`), verified by test.
- Set once in `MarcdownApp.init`: wiki links, `![[embeds]]`, LaTeX (`$..$`, `$$..$$`), `->` to arrow substitution
  are off. `==highlight==` and `@directives` are opt-in upstream and not registered. `~~strike~~` is registered.
  Auto-close of `(`, `[`, `{` is off; smart quotes are off.
- **Binding**: after each edit the coordinator computes the storage string and does
  `DispatchQueue.main.async { self.text = storage }` (only when it differs from the last synced text). The document
  therefore lags the text view by one run-loop turn. In `updateNSView`, if `text` differs from what the engine
  last synced, the engine rebuilds the whole storage (`rebuildTextStorageAndStyle`), so never write a stale value
  into `document.text` from outside.
- **Undo**: the engine keeps its own undo manager per `documentId`. ContentView uses a per-window constant id so
  Save As keeps undo. Edits via `shouldChangeText`/`didChangeText` are recorded normally.
- **Engine typing helpers** still active: list continuation, Tab indent, Enter in tables inserts `<br>`, task
  checkbox toggling, blockquote-aware paste. Engine's own paste tries, in order: `onPasteImage` (unused), its raw
  Markdown flavor, HTML (only with block structure) via its own converter, plain string, file text. `onWillPaste`
  runs before all of that.
- **Shortcuts**: the engine binds none of Marcdown's shortcuts (no key equivalents, only Cmd-Return for wiki previews).
  Standard NSTextView keys apply (e.g. Cmd-Z, Cmd-A, Option-arrows). SwiftUI `Commands` shortcuts win because
  menu key equivalents are matched first. The engine also listens for bus notifications (`MarkdownEditorBus`, e.g.
  `applyBoldRequest`) and has `didMarkdownBold` etc. on its coordinator; they are not wired here and their toggle
  logic is engine-internal, so implement toggles yourself on the raw text.
- **TextKit 2** (no `layoutManager`): `textView.textLayoutManager`, `textContentManager`. Per-line geometry:
  ```swift
  let tlm = textView.textLayoutManager!
  let start = tlm.textContentManager!.location(tlm.documentRange.location, offsetBy: charIndex)!
  tlm.ensureLayout(for: NSTextRange(location: start))
  tlm.enumerateTextSegments(in: NSTextRange(location: start), type: .standard, options: []) { _, frame, _, _ in ... }
  ```
  Frames are in text-container coordinates; add `textView.textContainerOrigin` for view coordinates. The scroll
  view's document view is a `NativeTextViewContainer` (the text view is its subview), so use
  `textView.convert(_, to:)` when moving into scroll-view space. Hidden syntax is shrunk, not removed, so a
  line's height/width reflect the styled text. `textView.enclosingScrollView` gives the scroll view.
- The text view's delegate is the engine's coordinator. Do not replace it. Use notifications
  (`NSText.didChangeNotification`, `NSTextView.didChangeSelectionNotification`) to observe.
- Relative Markdown links `[t](a.md)` are styled as links but the engine does not open them; not handled.
- `usesFindBar` is on (Cmd-F uses the standard find bar over the raw text).
