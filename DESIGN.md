# Marc — design

The simplest possible macOS Markdown editor. The name is "Marc" everywhere (app, bundle, CLI `marc`). Never use "Hash".

## Platform
- macOS 26 only, Swift 6 language mode, Xcode 27.
- Xcode project (`Marc.xcodeproj`) with SPM dependencies. Folders are synchronized groups, so new files need no project edits.
- Personal local build. No App Sandbox. No signing beyond "Sign to Run Locally".
- Bundle id: `one.m8n.marc`.

## Layout
```
Marc.xcodeproj
Makefile
App/                 SwiftUI app target "Marc"
  MarcApp.swift, Main.swift   `Window` scene, app delegate, document controller start
  OpenFiles.swift        open-files store (with the sidebar rows and order) + MarcDocumentController
  MarcFile.swift         NSDocument for one open file, with its per-file state
  MainWindow.swift       main window accessor and close handling
  FileCommands.swift     File menu, Window > Previous/Next File, pinned files
  Features/Formatting/   format on save, front matter split
  Features/Lint/         lint rules + gutter icons
  Features/Sidebar/      pinned and open-files list (row model, labels, drop to open)
  Features/Outline/      outline section of the sidebar
  Features/Pins/         pinned files: bookmark store
  Features/Reload/       outside file changes: reload, merge, ask
  Features/Shortcuts/    toggle commands
  Features/DropPaste/    drag/drop + HTML paste
  Features/Find/         Edit > Find menu (find bar)
  Features/Print/        Print and Export as PDF (HTML in an off-screen WKWebView)
  Features/WindowFrame/  the main window opens at its last size and position
  AppIcon.icon           Icon Composer app icon: bold "M"; white on neon orange (light), orange on black (dark/tinted)
Resources/marc       CLI shell script, copied into Marc.app/Contents/Resources
Tests/               unit test target "MarcTests"
Packages/MarkdownEngine/   vendored fork of nodes-app/swift-markdown-engine (+ NOTICE with upstream commit)
```

## Dependencies
- `Packages/MarkdownEngine` (local fork). Editor: `NativeTextViewWrapper`, TextKit 2, live preview (hides syntax).
- `apple/swift-markdown`: formatter, outline and lint parsing (source ranges).
- `steipete/Demark`: HTML → Markdown on paste (async, main actor).
- `swiftlang/swift-cmark` (products `cmark-gfm`, `cmark-gfm-extensions`): Markdown → HTML for printing. Already under swift-markdown; linked directly because swift-markdown's `HTMLFormatter` does not escape text or code.

## Engine fork changes
- Public hook to get the underlying `NSTextView` when it is ready.
- Paste interception hook and drop interception hook.
- Image base URL: relative image paths resolve against the folder of the .md file.
- Wiki-links, `![[embeds]]`, LaTeX, `==highlight==`, `@directives` off where possible. Plain GFM only.
- Remove engine key bindings that conflict with our shortcuts.
- `documentId` = the file's `MarcFile.id` (a UUID string), so undo and scroll position stay per file through Save As and renames. `retainedScrollDocumentIds` = the open files; a closed file drops its undo.
- Text binding capture: the coordinator takes the new `text` binding on every `updateNSView` (`setTextBinding`), and its async text pushes (`scheduleTextPush`) capture the binding and `documentId` when they are queued. A push queued just before a file switch lands in its own file, not in the new one.
- `configuration.paragraph` updates at runtime (upstream: only at creation).
- Element styles come from `MarkdownEditorTheme` (Marc: `MarkdownEditorTheme.marc` in `App/Features/Appearance/EditorTheme.swift`; picks in `docs/design/element-styles.html`): code blocks = full-width slab (`.codeBlockBackground` attribute, not color matching; `codeBlock.backgroundOutset` reaches into the inset; language in the top-right corner while the fence is hidden), inline code = rounded orange pill (`.inlineCodeBackground`, kerned padding), tables = rounded card with header fill and striped rows, block quotes = panel with bar and rounded right corners per nesting level (`.blockquoteEdges`). `SyntaxHighlighter.backgroundColor()` is gone.

## Architecture: one window, many files
- **Scene**: one `Window("Marc", id: "main")`, no `DocumentGroup`, no window tabs (`NSWindow.allowsAutomaticWindowTabbing = false`). Closing the window closes all files, then only hides it (`MainWindow.swift`); the next opened file brings it back. A launch from Finder or `open -a` does not open the scene, so `OpenFiles.openMainWindow` (SwiftUI's `openWindow`, set in FileCommands) creates it. No restoration of open files across launches.
- **`OpenFiles`** (`@Observable`, `OpenFiles.shared`): the open files in open order and `selectedID`. The window shows the selected file. Opening an open file selects it. After a close the row below is selected, else the row above. The last close shows an empty state; ⌘W in the empty state closes the window.
- **`MarcFile: NSDocument`**: one open file, UTF-8, `autosavesInPlace`. It has no window controllers: `showWindows` adds it to `OpenFiles` and selects it, `close` removes it, `windowForSheet` is the main window. So every way AppKit opens or creates a document (Open, Open Recent, Finder, Dock, `open -a`, New, Duplicate, web clip) ends in the store. NSDocument still does reading, saving, autosave and recents. Per-file state: `text`, observable `url` (mirror of `fileURL`), `isDirty`, `needsDiskReview`, `mergeNotice`, `outline` and `lintIssues` (computed off the main thread when `text` or `url` changes, debounced while typing, also for files not shown), `reloader`, `lastKnownDisk`.
- **`MarcDocumentController`** (created in Main.swift before the app starts, so it is `NSDocumentController.shared`): mirrors recents into the store for File > Open Recent (read after launch, then updated per new entry without resolving the bookmarks again), and replaces AppKit's quit review with `OpenFiles.closeAll`.
- **Closing**: ⌘W, the row's ×, the red close button and ⌘Q use `OpenFiles.close`. A file with a URL autosaves and closes silently. An untitled file with text asks Save / Don't Save / Cancel (our own alert; Don't Save leaves no draft). An empty untitled file closes silently. A file that waits for a disk review is selected (its question shows) and stays open. Close all asks for those files first, so Cancel leaves every file open.
- **Editor**: one engine instance and one `EditorController` for the window. The controller acts on the selected file (`controller.file`); save, print and reload get the document from it, never from `window.windowController.document`. The engine keeps undo, scroll position and selection per `documentId`. When it shows a file it calls `onDocumentShown`, and the controller shows the file's lint marks and, if a disk review waits, checks the disk (`fileShown`).
- **Outside changes** (`Features/Reload`): NSDocument's file presenter watches every open file (also after moves and Save As, and it does not report our own saves). `MarcFile.presentedItemDidChange` (without `super`, so NSDocument does not revert) reads the file on the presenter's queue and gives the text to the file's `FileReloader` on the main thread. The pure `ReloadPolicy` decides: shown clean file → reload in the text view; shown dirty file → Merge / Reload / Keep My Edits; background clean file → take the disk text silently (the engine drops its undo when it shows it again); background dirty file → `needsDiskReview`, a row marker, and the question when the file is selected. Autosave does nothing while `needsDiskReview`, so it never overwrites the outside change. A save to the file sets `lastKnownDisk`.

## Features
1. **Documents**: one window with all open files (see Architecture). Types `.md` and `.markdown` (`net.daringfireball.markdown`), and `.txt` (plain text, rank Alternate, open only), new document = `.md`. File menu: New, Open…, Open Recent, Close, Save, Duplicate, Move To…. File > Pin File / Unpin File ⌥⌘P. Window menu: Previous File ⇧⌘[, Next File ⇧⌘], the pinned files ⌥⌘1–⌥⌘9. ⌘1–6 stay headings.
2. **Format on save** (explicit ⌘S only, not autosave): swift-markdown `MarkupFormatter`. Options: unordered marker `-`, ordered incrementing from 1, emphasis `*` (strong `**`), ATX headings, code fences always with ```, thematic break `---`, no line limit, condense autolinks. YAML front matter (`---` … `---` at file start) is split off and kept verbatim. The buffer replacement goes through the undo manager (⌘Z reverts it). The cursor keeps its line/column.
3. **Lint while typing** (debounced): rules = broken relative link/image target (file does not exist), heading level jump (e.g. H1 → H3). Show a tiny, subtle icon on the line. Clicking it expands the message. Skip front matter.
4. **Sidebar**: left column of the `NavigationSplitView`, native `List` with `.sidebar` style, toggle ⌃⌘S. It opens by itself when the file count goes from one or none to more than one, or a pin appears (`OpenFiles.opensSidebar`), also when the window opens with several files or pins. It never closes by itself, so a ⌃⌘S hide holds until that turns false and true again.
   - **Pinned** section (hidden without pins), above Open Files: one row per pinned file, in pin order. A pin is a bookmark, kept in UserDefaults across launches and when the file closes; it follows renames and moves. Only files with a URL can be pinned. An open pinned file looks and acts like an Open Files row (dot, ×, disk marker; × closes the file, the pin stays). A closed pin looks the same, without dot and ×; a click opens it (`OpenFiles.activate`). Right-click any file row: Pin / Unpin; File > Pin File ⌥⌘P does the same for the shown file. A pinned file shows only here. Unpinning an open file moves it to the end of Open Files. ⌥⌘1–⌥⌘9 (Window menu) open or select pin 1–9. If a pin's file is gone when it is activated, the pin is removed and a capsule at the bottom of the window says so for a few seconds (`OpenFiles.missingPinNotice`). ⇧⌘[ and ⇧⌘] and the selection after a close follow the sidebar order (open pinned files, then the others; `OpenFiles.sidebarOrder`).
   - **Open Files** section, with the count of its rows: one row per unpinned file in open order. Label = file name without extension (untitled: NSDocument display name). Names that collide (across both sections) also show the parent folder in secondary color, more folders while those collide too (`FileLabels`). Tooltip = full path. Unsaved dot when dirty; on hover a × replaces it (same close as ⌘W). A file changed on disk with unsaved edits while not shown has an orange marker. Selection goes through `OpenFiles.selectedID`; a row in Pinned selects its pin (`SidebarItem`), so a click goes through `OpenFiles.activate`. Dropping Markdown or plain-text files (by type, not source code or JSON) on the sidebar opens them (a drop on the editor inserts links, see 6).
   - **Outline** section (hidden in the empty state): headings of the shown file, indented by level, kept per file. Click = move cursor to the heading and scroll to it. Skip front matter.
5. **Shortcuts** (toggle: apply if absent, remove if present; bold/italic with empty selection work on the word at the cursor):
   ⌘1…⌘6 heading 1–6 (again = paragraph), ⌘0 paragraph, ⌘B bold, ⌘I italic, ⌘⇧X strikethrough, ⌘E inline code, ⌘⇧C code block, ⌘K link (URL from pasteboard if present), ⌘' quote, ⌘⇧8 bullet list, ⌘⇧7 numbered list, ⌘⇧T task, ⌘⇧- rule.
6. **Drag & drop**: image file → `![name](relative/path)`; other file → `[filename](relative/path)`, inserted at drop point. Paths relative to the .md folder; unsaved document → absolute path. Paths with spaces use `<...>`.
7. **Paste**: ⌘V with HTML on the pasteboard → convert with Demark and insert Markdown. ⌥⇧⌘V = plain text paste.
8. **Find**: Edit > Find menu drives the text view's find bar: ⌘F find, ⌥⌘F find and replace, ⌘G / ⇧⌘G next / previous, Use Selection for Find (no shortcut: ⌘E is Code). Works also when the outline has focus.
9. **CLI `marc`**: shell script in `Marc.app/Contents/Resources/marc`: create missing files (`touch`), then `open -a Marc "$@"`. An `http(s)://` argument runs `Marc --clip <url>` headless (`App/Main.swift`, `App/WebClip.swift`): Demark loads the page (`main`/`[role=main]`/`article` if present, without `nav`/`footer`), links become absolute, empty links go, the text is formatted like ⌘S and written to `<slug of first H1>.md` in a temporary folder; the script opens the printed `marc://clip?file=<path>` URL, and the app opens the text as a new untitled file in the main window, named like the file (`NSDocumentController.makeDocument(for: nil, withContentsOf:ofType:)` and `showWindows`, so it goes into `OpenFiles` and Save proposes the slug), and deletes the temporary folder. Nothing is saved until you save. Menu item "Install Command Line Tool…" symlinks it into `~/.local/bin/marc`.
10. **Print**: File > Print… (⌘P), Export as PDF…, Page Setup… (⇧⌘P) replace the system items (those print the editor view: screen colours, window width, hidden syntax). The text (without front matter) goes through cmark-gfm (tables, `~~strikethrough~~`, task lists, autolinks, raw HTML kept) into an HTML page with a light print stylesheet and the editor font family. `<base>` = document folder, so relative images work. An off-screen `WKWebView` (JavaScript off) loads it from a temp file and runs `printOperation` modal for the window (`run()` gives blank pages). Export as PDF: save panel, then the same operation with `jobDisposition = .save` (paginated, not one long page).
11. **Window frame**: moving or resizing the main window saves its frame (`NSWindow.saveFrame(usingName: "DocumentWindow")`, not in full screen). The window opens at that frame, also after relaunch.
12. **Makefile**: `run` (quit running Marc, build Debug, launch), `install` (build Release, copy to `/Applications/Marc.app`, symlink `marc` into `$(PREFIX)/bin`, `PREFIX ?= $(HOME)/.local`), `test`, `build`, `clean`.
13. **Tests**: unit tests for pure logic (toggle commands, path building, front matter split, lint rules, outline extraction, print HTML, reload policy, merge, sidebar labels, pins), the `OpenFiles` store, `MarcFile`, and file switches in an off-screen engine. No UI tests.
