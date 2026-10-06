# Marc

<p align="center">
  <img src="docs/app-icon.png" alt="Marc app icon" width="128">
</p>

A small Markdown window for the terminal. Type `marc notes.md`, and the file opens in a native macOS window with a live preview. Marc is a free macOS app.

Marc has a very limited feature set, and it is very opinionated. It is mostly a graphical user interface that you control from the command line, and only then a Markdown editor. It is not a fully featured Markdown editor, and it will not become one.

<p align="center">
  <img src="docs/marc.png" alt="Marc shows a pizza dough recipe with headings, lists, a quote, and tasks. Two small lint icons in the right margin mark a heading level jump and a broken link." width="480">
</p>

## Why Marc

I live in the terminal. For code, a terminal editor is good. For Markdown, I want to see the text the way that it reads: headings, lists, links, and images. The big Markdown apps have libraries, sync, themes, and plugins. I only want to open a file, write, and close the window.

## Opinions

Marc makes the decisions for you. There are no settings.

- **Plain GitHub Flavored Markdown** — no wiki-links, no embeds, no LaTeX, no `==highlight==`.
- **One style** — when you save with `⌘S`, Marc formats the file: `-` for bullets, `*` for
  emphasis, `#` headings, fenced code blocks, `---` for rules. YAML front matter stays as it is.
  `⌘Z` reverts the format. Autosave does not format.
- **Live preview** — Marc hides the Markdown syntax while you type. The editor is the main
  preview. A rendered view and a split view are extras to see the final result.
- **Two lint rules** — a link or image to a file that does not exist, and a heading level jump
  (for example H1 to H3). A small icon shows on the line. Click it to see the message.

## Install

Marc needs macOS 26 or later. Install it with Homebrew:

```sh
brew tap marcboeker/marc https://github.com/marcboeker/marc
brew trust --cask marcboeker/marc/marc
brew install --cask marc
```

This installs `Marc.app` to `/Applications` and puts the `marc` command in the Homebrew `bin`
folder.

To build Marc yourself, see [docs/BUILD.md](docs/BUILD.md).

## The `marc` command

```sh
marc                      # open Marc
marc README.md            # open a file
marc todo.md ideas.md     # open more files, each in its own window
marc new-note.md          # the file does not exist: Marc makes an empty file and opens it
marc https://example.com  # load a web page as Markdown into a new, unsaved document
```

- A missing file is made empty before it opens. Its folder must exist.
- A web page URL gives a new, unsaved document. Marc keeps only the main content of the page, and it removes navigation and footers. When you save, Marc proposes a file name from the first heading.
- Options such as `-n` (new app instance) or `-g` (keep the terminal in front) go to `open`.

## Features

- **Command line** — open files and web pages from the terminal. See
  [The `marc` command](#the-marc-command).
- **Outline** — a sidebar with the headings of the document.
- **Pinned files** — keep files at the top of the sidebar. `⌘D` pins, `⌥⌘1` to `⌥⌘9` open.
- **Drag and drop** — drop an image or a file to insert a relative link.
- **Paste from the web** — `⌘V` changes copied HTML into Markdown.
- **Preview and source** — a rendered preview, a side-by-side view, and a raw Markdown view.
- **Command launcher** — `⇧⌘P` finds menu commands and files by name. The ones you used last
  come first.
- **Print and PDF** — most Markdown editors cannot print. Marc prints the rendered document
  (`⌘P`) and exports it as PDF.

## Shortcuts

Each shortcut is a toggle: press it again to remove the format. Bold and italic without a
selection apply to the word at the cursor.

| Shortcut | Format |
| --- | --- |
| `⌘1` to `⌘6` | Heading 1 to 6 |
| `⌘0` | Paragraph |
| `⌘B` | Bold |
| `⌘I` | Italic |
| `⌘⇧X` | Strikethrough |
| `⌘E` | Inline code |
| `⌘⇧C` | Code block |
| `⌘K` | Link (uses the URL from the clipboard, if there is one) |
| `⌘'` | Quote |
| `⌘⇧8` | Bullet list |
| `⌘⇧7` | Numbered list |
| `⌘⇧T` | Task |
| `⌘⇧-` | Horizontal rule |

These shortcuts change the view:

| Shortcut | View |
| --- | --- |
| `⌃⌘P` | Preview: the rendered document in place of the editor |
| `⌥⌘P` | Side by Side: editor and rendered document |
| `⌥⌘U` | Show Markdown Source: all syntax, one font size |
| `⌃⌘S` | Sidebar |

More shortcuts:

| Shortcut | Action |
| --- | --- |
| `⇧⌘P` | Command Launcher: type to find a menu command or a file, `Return` runs it |
| `⌥⇧⌘P` | Page Setup |

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Credits

The editor and its live preview use
[swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine). Marc includes a modified copy in
[Packages/MarkdownEngine](Packages/MarkdownEngine). The changes are listed in its
[NOTICE](Packages/MarkdownEngine/NOTICE) file.

## License

MIT, see [LICENSE](LICENSE). The Markdown engine in
[Packages/MarkdownEngine](Packages/MarkdownEngine) has the Apache License 2.0, see
[its LICENSE](Packages/MarkdownEngine/LICENSE).
