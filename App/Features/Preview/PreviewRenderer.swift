import Foundation

extension DocumentStyle {
    /// The editor's look for the preview page: font, size, line spacing and line width.
    @MainActor
    init(settings: AppearanceSettings = .shared) {
        self.init(fontFamily: settings.htmlFontFamily, fontSize: settings.fontSize,
                  lineSpacing: settings.lineSpacing, lineWidth: settings.limitsLineWidth ? settings.lineWidth : nil)
    }
}

/// Markdown → the preview page. The same HTML as Print (MarkdownHTML), with source positions for
/// scrolling, and a screen stylesheet that follows the system light or dark appearance.
enum PreviewRenderer {
    /// The rendered body and where its elements come from.
    struct Rendering: Equatable {
        var body: PreviewBody
        var sourceMap: PreviewSourceMap

        var html: String { body.html }
    }

    /// Front matter is dropped; the source map counts its lines, so editor lines still match.
    static func render(markdown: String) -> Rendering {
        let parts = FrontMatterSplit.split(markdown)
        let body = PreviewBody(markdown: parts.body)
        let map = PreviewSourceMap(html: body.html, frontMatterLines: PreviewSourceMap.lineCount(of: parts.front), text: markdown)
        return Rendering(body: body, sourceMap: map)
    }

    /// The page loaded once. Later changes go through the script's `update`, without a reload.
    static func page(body: String, baseFolder: URL?, style: DocumentStyle) -> String {
        let base = baseFolder.map { "<base href=\"\(MarkdownHTML.escape(PreviewScheme.base($0)))\">\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(base)<style id="marc-style">
        \(stylesheet(style))
        </style>
        </head>
        <body>
        <main id="marc-body">\(body)</main>
        </body>
        </html>
        """
    }

    /// Colours follow `prefers-color-scheme`; the web view takes the app's appearance. The page
    /// padding is the editor's text inset.
    static func stylesheet(_ style: DocumentStyle) -> String {
        """
        :root { color-scheme: light dark; \(DocumentPalette.cssVariables(dark: false)) --check: \(DocumentStyle.checkImage(dark: false)); }
        @media (prefers-color-scheme: dark) {
            :root { \(DocumentPalette.cssVariables(dark: true)) --check: \(DocumentStyle.checkImage(dark: true)); }
        }
        html { background: transparent; }
        body { margin: 0; padding: 16px 24px 48px; }
        \(style.css(unit: "px"))
        """
    }

    /// Runs in its own content world; the page's JavaScript is off. `update` applies a
    /// `PreviewBody.Change`: Swift finds the changed top-level blocks, the page replaces only them
    /// (no flash, scroll stays). Headings get GitHub-style ids for `#name` links.
    static let script = #"""
    (() => {
        // The body's top-level blocks as Swift split them, each a list of nodes.
        // Null until the first change after a load finds them in the page.
        let blocks = null;

        function setBase(href) {
            let base = document.querySelector('base');
            if (!href) { if (base) base.remove(); return; }
            if (!base) { base = document.createElement('base'); document.head.prepend(base); }
            if (base.getAttribute('href') !== href) base.setAttribute('href', href);
        }

        // The loaded page's nodes in `count` blocks: a block starts at the element with its first position.
        function split(root, count, starts) {
            const result = Array.from({ length: count }, () => []);
            let index = 0;
            for (const node of root.childNodes) {
                if (index + 1 < count && node.nodeType === 1 && node.getAttribute('data-sourcepos') === starts[index]) index++;
                if (index >= count) return null;
                result[index].push(node);
            }
            return count === 0 || index === count - 1 ? result : null;
        }

        // The number of new blocks put in, or -1 when the page's blocks are not the ones Swift has.
        function setBody(root, change) {
            if (change.full) {
                root.replaceChildren();
                blocks = [];
            } else if (!blocks && change.starts) {
                blocks = split(root, change.count, change.starts);
            }
            if (!blocks || blocks.length !== change.count) {
                blocks = null;
                return -1;
            }
            const end = change.start + change.removed;
            const after = blocks.slice(end).find(nodes => nodes.length)?.[0] ?? null;
            for (const nodes of blocks.slice(change.start, end)) for (const node of nodes) node.remove();
            const fresh = change.html.map(html => {
                const template = document.createElement('template');
                template.innerHTML = html;
                const nodes = Array.from(template.content.childNodes);
                root.insertBefore(template.content, after);
                return nodes;
            });
            blocks = [...blocks.slice(0, change.start), ...fresh, ...blocks.slice(end)];
            for (const [index, positions] of change.positions) {
                const elements = blocks[index].flatMap(node => node.nodeType === 1
                    ? [node, ...node.querySelectorAll('[data-sourcepos]')].filter(e => e.hasAttribute('data-sourcepos'))
                    : []);
                positions.forEach((position, i) => elements[i]?.setAttribute('data-sourcepos', position));
            }
            if (fresh.length || change.removed) addHeadingIDs(root);
            return fresh.length;
        }

        function slug(text) {
            return text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
        }

        function addHeadingIDs(root) {
            const used = new Map();
            for (const heading of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
                const base = slug(heading.textContent);
                const count = used.get(base) || 0;
                used.set(base, count + 1);
                heading.id = count ? `${base}-${count}` : base;
            }
        }

        window.marcPreview = {
            update(base, css, change) {
                setBase(base);
                const style = document.getElementById('marc-style');
                if (style.textContent !== css) style.textContent = css;
                return setBody(document.getElementById('marc-body'), change);
            },
            // Put `fraction` of the element at the top of the window, below the page padding.
            scrollToBlock(position, fraction) {
                const element = document.querySelector(`[data-sourcepos="${CSS.escape(position)}"]`);
                if (!element) return;
                const rect = element.getBoundingClientRect();
                window.scrollTo(0, Math.max(0, window.scrollY + rect.top + rect.height * fraction - 16));
            },
            scrollToAnchor(name) {
                const element = document.getElementById(name) || document.getElementsByName(name)[0]
                    || document.getElementById(slug(name));
                if (element) element.scrollIntoView({ block: 'start' });
            },
            // The find match (the selection) in the middle of the window.
            centerSelection() {
                const selection = window.getSelection();
                if (!selection.rangeCount) return;
                const rect = selection.getRangeAt(0).getBoundingClientRect();
                if (!rect.height) return;
                window.scrollTo(0, Math.max(0, window.scrollY + rect.top + rect.height / 2 - window.innerHeight / 2));
            },
            selectedText() { return String(window.getSelection() || ''); },
            clearSelection() { window.getSelection().removeAllRanges(); },
        };
        addHeadingIDs(document.getElementById('marc-body'));
    })();
    """#
}
