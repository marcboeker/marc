//
//  MarkdownEditorTheme.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Color palette for the Markdown editor engine.
//
//  All user-visible colors used by the engine are routed through this
//  struct. Defaults map to system colors so the editor adapts to light/
//  dark mode automatically. Embedders that want a custom palette (for
//  example, a sepia or high-contrast preset) can replace any subset of
//  the colors without touching engine source files.
//

import AppKit
import Foundation

// MARK: - Theme

/// Color palette consumed by the Markdown editor engine.
///
/// Every color the engine puts on screen is read from this struct, so a
/// single override is enough to retheme the entire editor. The defaults
/// reproduce a system-native macOS look using `NSColor` dynamic system
/// colors, so light/dark-mode switching keeps working without extra code.
public struct MarkdownEditorTheme: Sendable {

    // MARK: Text colors

    /// Foreground color for plain body text and the typing caret.
    public var bodyText: NSColor
    /// Foreground color for de-emphasized text and most syntax markers.
    /// Defaults to `secondaryLabelColor` so it tracks the system style.
    public var mutedText: NSColor
    /// Foreground color for content the engine wants to deemphasize further
    /// than `mutedText` — for example, broken wiki-links.
    public var disabledText: NSColor
    /// Foreground color for heading marker glyphs (`#`, `##`, …).
    public var headingMarker: NSColor

    // MARK: Links

    /// Foreground color for hyperlinks that resolve to an URL.
    public var link: NSColor
    /// Foreground color for incomplete `[text]` patterns (no URL yet).
    public var incompleteLink: NSColor

    // MARK: Find / search highlights

    /// Background color used to highlight all matches when the user is
    /// running an in-document search.
    ///
    /// The default is `.systemYellow` so embedders that don't customize
    /// this still get a sensible result. Apps with their own brand color
    /// (for example, the Nodes app uses its custom yellow) should override
    /// this to match their palette.
    public var findMatchHighlight: NSColor
    /// Background color used to highlight the currently-focused match
    /// during in-document search. Typically a stronger version of
    /// ``findMatchHighlight``.
    public var findCurrentMatchHighlight: NSColor

    // MARK: LaTeX rendering

    /// Foreground color used when rendering LaTeX formulas in light mode.
    public var latexLightModeText: NSColor
    /// Foreground color used when rendering LaTeX formulas in dark mode.
    public var latexDarkModeText: NSColor

    // MARK: Strikethrough / decoration

    /// Stroke color used for strikethrough decorations
    /// (e.g. completed task list items, horizontal rules).
    public var strikethroughColor: NSColor

    // MARK: Highlight

    /// Background color used for `==highlight==` inline markup.
    public var highlightColor: NSColor

    // Marc: the code, block quote and table colors below are new. Upstream took the code fill from
    // `SyntaxHighlighter.backgroundColor()` and drew quote bars and table lines in `mutedText`.

    // MARK: Code

    /// Fill behind fenced code blocks.
    public var codeBlockBackground: NSColor
    /// Color of the language name drawn in a code block's corner while the
    /// opening fence is hidden.
    public var codeBlockLanguage: NSColor
    /// Rounded fill behind inline `` `code` `` spans.
    public var inlineCodeBackground: NSColor
    /// Ink for inline code. `nil` keeps the surrounding text color.
    public var inlineCodeText: NSColor?

    // MARK: Block quotes

    /// Vertical bar in a block quote's left gutter, one per nesting level.
    public var blockquoteBar: NSColor
    /// Panel fill behind block quote lines. `nil` draws the bar only.
    public var blockquoteBackground: NSColor?
    /// Ink for block quote content.
    public var blockquoteText: NSColor

    // MARK: Tables

    /// Rules between a rendered table's rows.
    public var tableBorder: NSColor

    // Marc: new keys. nil keeps the look from before them.

    // MARK: Rules and markers

    /// Line under a table's header row. nil: `tableBorder`.
    public var tableHeaderRule: NSColor?
    /// Thematic-break rule. nil: `strikethroughColor` at 40 %.
    public var rule: NSColor?
    /// Drawn `•` bullets and ordered-list numbers. nil: `bodyText`.
    public var listMarker: NSColor?
    /// Link underline. nil: the link color.
    public var linkUnderline: NSColor?
    /// Text of a checked task item. nil: unchanged.
    public var taskDoneText: NSColor?

    // MARK: Init

    public init(
        bodyText: NSColor = .labelColor,
        mutedText: NSColor = .secondaryLabelColor,
        disabledText: NSColor = .tertiaryLabelColor,
        headingMarker: NSColor = .gray,
        link: NSColor = .linkColor,
        incompleteLink: NSColor = .systemBlue,
        findMatchHighlight: NSColor = .systemYellow,
        findCurrentMatchHighlight: NSColor = .systemYellow,
        latexLightModeText: NSColor = .black,
        latexDarkModeText: NSColor = .white,
        strikethroughColor: NSColor = .labelColor,
        highlightColor: NSColor = .systemOrange.withAlphaComponent(0.4),
        // Marc: new colors.
        codeBlockBackground: NSColor = .overlay(dark: 0.055, light: 0.035),
        codeBlockLanguage: NSColor = .tertiaryLabelColor,
        inlineCodeBackground: NSColor = .overlay(dark: 0.09, light: 0.06),
        inlineCodeText: NSColor? = nil,
        blockquoteBar: NSColor = .secondaryLabelColor.withAlphaComponent(0.5),
        blockquoteBackground: NSColor? = nil,
        blockquoteText: NSColor = .secondaryLabelColor,
        tableBorder: NSColor = .overlay(dark: 0.12, light: 0.10),
        tableHeaderRule: NSColor? = nil,
        rule: NSColor? = nil,
        listMarker: NSColor? = nil,
        linkUnderline: NSColor? = nil,
        taskDoneText: NSColor? = nil
    ) {
        self.bodyText = bodyText
        self.mutedText = mutedText
        self.disabledText = disabledText
        self.headingMarker = headingMarker
        self.link = link
        self.incompleteLink = incompleteLink
        self.findMatchHighlight = findMatchHighlight
        self.findCurrentMatchHighlight = findCurrentMatchHighlight
        self.latexLightModeText = latexLightModeText
        self.latexDarkModeText = latexDarkModeText
        self.strikethroughColor = strikethroughColor
        self.highlightColor = highlightColor
        // Marc: new colors.
        self.codeBlockBackground = codeBlockBackground
        self.codeBlockLanguage = codeBlockLanguage
        self.inlineCodeBackground = inlineCodeBackground
        self.inlineCodeText = inlineCodeText
        self.blockquoteBar = blockquoteBar
        self.blockquoteBackground = blockquoteBackground
        self.blockquoteText = blockquoteText
        self.tableBorder = tableBorder
        self.tableHeaderRule = tableHeaderRule
        self.rule = rule
        self.listMarker = listMarker
        self.linkUnderline = linkUnderline
        self.taskDoneText = taskDoneText
    }

    /// System-native palette built from `NSColor` dynamic system colors.
    ///
    /// Use this if you want the engine to look like a stock macOS
    /// `NSTextView`. It's also the default when no theme is supplied.
    public static let `default` = MarkdownEditorTheme()
}

// Marc: new helper for the default theme colors.
extension NSColor {
    /// Text-colored wash: white at `dark` alpha on a dark appearance, black at
    /// `light` alpha on a light one. Tints any background the same way.
    public static func overlay(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .white.withAlphaComponent(dark)
                : .black.withAlphaComponent(light)
        }
    }
}
