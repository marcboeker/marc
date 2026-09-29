# Marc — design

The simplest possible macOS Markdown editor. The name is "Marc" everywhere (app, bundle, CLI `marc`). Never use "Hash".

## Platform
- macOS 26 only, Swift 6 language mode, Xcode 27.
- Xcode project (`Marc.xcodeproj`) with SPM dependencies. Folders are synchronized groups, so new files need no project edits.
- Personal local build. No App Sandbox. No signing beyond "Sign to Run Locally".
- Bundle id: `net.at6.marc`.

## Layout
```
Marc.xcodeproj
Makefile
App/                 SwiftUI app target "Marc"
  Features/Formatting/   format on save, front matter split
  Features/Lint/         lint rules + gutter icons
  Features/Outline/      outline sidebar
  Features/Shortcuts/    toggle commands
  Features/DropPaste/    drag/drop + HTML paste
  Features/Find/         Edit > Find menu (find bar)
  Features/Print/        Print and Export as PDF (HTML in an off-screen WKWebView)
  Features/WindowFrame/  new windows open at the last window size and position
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
- `documentId` = file URL string.
- `configuration.paragraph` updates at runtime (upstream: only at creation).
- Element styles come from `MarkdownEditorTheme` (Marc: `MarkdownEditorTheme.marc` in `App/Features/Appearance/EditorTheme.swift`; picks in `docs/design/element-styles.html`): code blocks = full-width slab (`.codeBlockBackground` attribute, not color matching; `codeBlock.backgroundOutset` reaches into the inset; language in the top-right corner while the fence is hidden), inline code = rounded orange pill (`.inlineCodeBackground`, kerned padding), tables = rounded card with header fill and striped rows, block quotes = panel with bar and rounded right corners per nesting level (`.blockquoteEdges`). `SyntaxHighlighter.backgroundColor()` is gone.

## Features
1. **Documents**: `DocumentGroup`, types `.md` and `.markdown` (`net.daringfireball.markdown`), new document = `.md`. Open, Save, Save As, recents, tabs from the system.
2. **Format on save** (explicit ⌘S only, not autosave): swift-markdown `MarkupFormatter`. Options: unordered marker `-`, ordered incrementing from 1, emphasis `*` (strong `**`), ATX headings, code fences always with ```, thematic break `---`, no line limit, condense autolinks. YAML front matter (`---` … `---` at file start) is split off and kept verbatim. The buffer replacement goes through the undo manager (⌘Z reverts it). The cursor keeps its line/column.
3. **Lint while typing** (debounced): rules = broken relative link/image target (file does not exist), heading level jump (e.g. H1 → H3). Show a tiny, subtle icon on the line. Clicking it expands the message. Skip front matter.
4. **Outline**: left sidebar, `NavigationSplitView`, toggle ⌃⌘S. Lists headings (indented by level). Click = move cursor to the heading and scroll to it. Skip front matter.
5. **Shortcuts** (toggle: apply if absent, remove if present; bold/italic with empty selection work on the word at the cursor):
   ⌘1…⌘6 heading 1–6 (again = paragraph), ⌘0 paragraph, ⌘B bold, ⌘I italic, ⌘⇧X strikethrough, ⌘E inline code, ⌘⇧C code block, ⌘K link (URL from pasteboard if present), ⌘' quote, ⌘⇧8 bullet list, ⌘⇧7 numbered list, ⌘⇧T task, ⌘⇧- rule.
6. **Drag & drop**: image file → `![name](relative/path)`; other file → `[filename](relative/path)`, inserted at drop point. Paths relative to the .md folder; unsaved document → absolute path. Paths with spaces use `<...>`.
7. **Paste**: ⌘V with HTML on the pasteboard → convert with Demark and insert Markdown. ⌥⇧⌘V = plain text paste.
8. **Find**: Edit > Find menu drives the text view's find bar: ⌘F find, ⌥⌘F find and replace, ⌘G / ⇧⌘G next / previous, Use Selection for Find (no shortcut: ⌘E is Code). Works also when the outline has focus.
9. **CLI `marc`**: shell script in `Marc.app/Contents/Resources/marc`: create missing files (`touch`), then `open -a Marc "$@"`. An `http(s)://` argument runs `Marc --clip <url>` headless (`App/Main.swift`, `App/WebClip.swift`): Demark loads the page (`main`/`[role=main]`/`article` if present, without `nav`/`footer`), links become absolute, empty links go, the text is formatted like ⌘S and written to `<slug of first H1>.md` in a temporary folder; the script opens the printed `marc://clip?file=<path>` URL, and the app opens the text as a new untitled document named like the file (`NSDocumentController.makeDocument(for: nil, withContentsOf:ofType:)`, so Save proposes the slug) and deletes the temporary folder. Nothing is saved until you save. Menu item "Install Command Line Tool…" symlinks it into `~/.local/bin/marc`.
10. **Print**: File > Print… (⌘P), Export as PDF…, Page Setup… (⇧⌘P) replace the system items (those print the editor view: screen colours, window width, hidden syntax). The text (without front matter) goes through cmark-gfm (tables, `~~strikethrough~~`, task lists, autolinks, raw HTML kept) into an HTML page with a light print stylesheet and the editor font family. `<base>` = document folder, so relative images work. An off-screen `WKWebView` (JavaScript off) loads it from a temp file and runs `printOperation` modal for the window (`run()` gives blank pages). Export as PDF: save panel, then the same operation with `jobDisposition = .save` (paginated, not one long page).
11. **Window frame**: moving or resizing a document window saves its frame (`NSWindow.saveFrame(usingName: "DocumentWindow")`, not in full screen). A new window opens at that frame, also after relaunch; it moves down-right by 22 pt while another window is at the same origin. A new tab keeps the frame of its tab group.
12. **Makefile**: `run` (quit running Marc, build Debug, launch), `install` (build Release, copy to `/Applications/Marc.app`, symlink `marc` into `$(PREFIX)/bin`, `PREFIX ?= $(HOME)/.local`), `test`, `build`, `clean`.
13. **Tests**: unit tests for pure logic only (toggle commands, path building, front matter split, lint rules, outline extraction, print HTML). No UI tests.
