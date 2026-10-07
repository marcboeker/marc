//
//  MarkdownTextLayoutFragment.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 12.04.26.
//
//  TextKit 2 replacement for CodeBlockLayoutManager.
//  Draws code-block backgrounds, LaTeX images, and task checkboxes
//  via NSTextLayoutFragment instead of NSLayoutManager glyph overrides.

import AppKit
import CoreText

// MARK: - Custom attribute keys for rendering overlays

extension NSAttributedString.Key {
    static let latexImage = NSAttributedString.Key("LatexRenderedImage")
    static let latexBounds = NSAttributedString.Key("LatexImageBounds")
    static let latexIsBlock = NSAttributedString.Key("LatexIsBlock")
    static let latexBlockOffsetY = NSAttributedString.Key("LatexBlockOffsetY")
    static let thematicBreak = NSAttributedString.Key("ThematicBreak")
    /// String — the mark to draw CENTERED in place of the full-width rule on a
    /// line that already carries `.thematicBreak`. Absent means the rule. The
    /// styler resolves it from `configuration.thematicBreak`, so the fragment
    /// draws what it is told and never re-reads the marker character.
    static let thematicBreakMark = NSAttributedString.Key("ThematicBreakMark")
    /// CGFloat — the mark's size as a multiple of the body font. Absent = 1.
    static let thematicBreakMarkScale = NSAttributedString.Key("ThematicBreakMarkScale")
    /// Int nesting level (1-based) of a blockquote line; the fragment
    /// paints that many vertical bars in the left gutter.
    static let blockquoteLevel = NSAttributedString.Key("BlockquoteLevel")
    // Marc: new keys (blockquoteEdges, codeBlockBackground, codeBlockLanguage, inlineCodeBackground).
    /// [Int] — one `BlockquoteEdge` mask per nesting level of a blockquote
    /// line: whether that level's panel opens and/or closes on this line.
    static let blockquoteEdges = NSAttributedString.Key("BlockquoteEdges")
    /// NSColor — marks every line of a fenced code block and carries its fill.
    static let codeBlockBackground = NSAttributedString.Key("CodeBlockBackground")
    /// String — the language of a code block whose opening fence is hidden,
    /// on the fence's first character. The fragment draws it in the corner.
    static let codeBlockLanguage = NSAttributedString.Key("CodeBlockLanguage")
    /// NSColor — rounded pill fill behind an inline code span (markers included).
    static let inlineCodeBackground = NSAttributedString.Key("InlineCodeBackground")
    /// Marks a bullet-list marker char (`-`/`*`/`+`) whose glyph is hidden so
    /// the fragment can paint a `•` in its place. Set to `true`.
    static let bulletMarker = NSAttributedString.Key("BulletListMarker")
    static let orderedMarker = NSAttributedString.Key("OrderedListMarker")
    /// CGFloat — natural image width; presence flags block as overlay-rendered.
    static let scrollableBlockNaturalWidth = NSAttributedString.Key("ScrollableBlockNaturalWidth")
    /// Int — hash of source text; key for overlay reconcile + offset persistence.
    static let scrollableBlockSourceID = NSAttributedString.Key("ScrollableBlockSourceID")
    /// CGFloat — total reserved height (image + scroller strip) for overlay sizing.
    static let scrollableBlockTotalHeight = NSAttributedString.Key("ScrollableBlockTotalHeight")
    /// NSValue(range:) — full multi-line range of a rendered table, used to scope width-change restyles.
    static let scrollableBlockFullRange = NSAttributedString.Key("ScrollableBlockFullRange")
}

public extension NSAttributedString.Key {
    /// NSColor — a background painted across the whole LINE BOX (the line
    /// fragment's typographic bounds) instead of the glyph box AppKit's
    /// `.backgroundColor` covers. Use it for marker-style fills: a span that
    /// wraps over several lines then reads as one solid block, at any font
    /// size and with any `paragraph.lineHeightExtraSpacing`, where
    /// `.backgroundColor` leaves a gap between every pair of lines.
    ///
    /// Painted by `MarkdownTextLayoutFragment`, so it renders in the editor
    /// only — table cells rasterize their own text and fall back to
    /// `.backgroundColor` (see `MarkdownStyler+Tables`).
    static let markdownBlockBackground = NSAttributedString.Key("MarkdownBlockBackground")
}

// Marc: new.
/// Bits of a `.blockquoteEdges` entry.
enum BlockquoteEdge {
    static let top = 1
    static let bottom = 2
}

final class MarkdownTextLayoutFragment: NSTextLayoutFragment {

    /// Horizontal space (points) each blockquote nesting level occupies —
    /// shared so the styler's text indent and the painted bars line up.
    /// Level N's bar sits where level N-1's text starts.
    static let blockquoteIndentPerLevel: CGFloat = 20 // Marc: upstream 18
    static let blockquoteBarWidth: CGFloat = 2 // Marc: upstream 3
    // Marc: new constants for quote panels and inline code pills.
    static let panelCornerRadius: CGFloat = 8 // Marc: also code blocks
    /// Horizontal room (points) the styler kerns in on each side of hidden
    /// inline-code content; the pill fills it.
    static let inlineCodePillPadding: CGFloat = 4

    /// Strip below an overlay block for the legacy-small scroller (~11pt) + buffer.
    static let scrollableBlockScrollerStrip: CGFloat = 14

    // MARK: - FB15131180

    /// Maps to TextKit-2's private `extraLineFragmentAttributes` selector so we can pin the trailing extra-line metrics to body font; otherwise a trailing heading paragraph inflates `usageBoundsForTextContainer` by ~30pt when the caret enters it. Pattern from STTextView.
    @objc(extraLineFragmentAttributes)
    dynamic var stExtraLineFragmentAttributes: NSDictionary?

    // MARK: - Rendering surface

    /// Extend rendering bounds for code-block backgrounds (full container width)
    /// and block images drawn below text via paragraphSpacing.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        // Task checkboxes too: the box draws left of the first glyph (marker
        // slot), outside the default text surface — TextKit would clip it.
        if hasCodeBlockBackground || hasThematicBreak || hasBlockquote || hasTaskCheckbox {
            let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
            // Extend left to container edge; a code block's fill reaches past it.
            // Marc: the outset (`CodeBlockStyle.backgroundOutset`) is new.
            let outset = hasCodeBlockBackground ? codeBlockOutset : 0
            bounds.origin.x = -layoutFragmentFrame.origin.x - outset
            bounds.size.width = containerWidth + 2 * outset
        }
        // Marc: quote panels reach into the paragraph spacing above and below.
        for panel in blockquotePanels(at: .zero) {
            bounds = bounds.union(panel.rect)
        }
        // Extend bounds to cover block images that render below the text line
        // (visibleSource mode uses paragraphSpacing to create space for the image).
        for rect in blockImageRects(at: .zero) {
            bounds = bounds.union(rect)
        }
        // Line-box fills are taller than the glyphs they sit behind.
        for fill in blockBackgroundFills(at: .zero) {
            bounds = bounds.union(fill.rect)
        }
        return bounds
    }

    // MARK: - Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        // 1. Code-block backgrounds (behind text)
        drawCodeBlockBackground(at: point, in: context)

        // 1a. Quote panels and bars (behind text — text is indented past the bars)
        //     Marc: upstream drew the bars only, as step 6.
        drawBlockquotePanels(at: point, in: context)

        // 1b. Line-box fills (`==highlight==` and friends), behind text
        drawBlockBackgrounds(at: point, in: context)

        // 1c. Inline code pills, behind text (Marc: new)
        drawInlineCodePills(at: point, in: context)

        // 2. LaTeX images (behind text — hidden markers are invisible anyway)
        drawLatexImages(at: point, in: context)

        // 3. Normal text
        super.draw(at: point, in: context)

        // 4. Task checkboxes (on top of hidden [ ]/[x] markers)
        drawTaskCheckboxes(at: point, in: context)

        // 4b. Bullet glyphs (on top of hidden -/*/+ markers)
        drawBulletMarkers(at: point, in: context)
        drawOrderedMarkers(at: point, in: context)

        // 5. Thematic breaks (full-width line, painted last so it doesn't
        //    fight with anything that already drew at the line's center)
        drawThematicBreaks(at: point, in: context)

        // 6. Code-block language label (top-right corner, hidden fence only) (Marc: new)
        drawCodeBlockLanguage(at: point, in: context)
    }

    // MARK: - Helpers

    /// NSRange in the document for this fragment's content.
    private var fragmentNSRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let start = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private var textStorage: NSTextStorage? {
        (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
    }

    /// Returns the drawing position for a character at `docIndex` (document-level NSRange location).
    /// `point` is the draw origin passed to `draw(at:in:)`.
    private func drawPosition(forDocumentCharAt docIndex: Int, point: CGPoint) -> (x: CGFloat, baselineY: CGFloat, lineHeight: CGFloat)? {
        guard let fragRange = fragmentNSRange else { return nil }
        let localIndex = docIndex - fragRange.location
        guard localIndex >= 0 else { return nil }

        // NSTextLineFragment.typographicBounds.origin.y is already relative to the
        // parent layout fragment, so we use it directly — accumulating per-line
        // heights would double-count the inter-line offset on wrapped lines.
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let charPos = lineFragment.locationForCharacter(at: localIndex)
                let tb = lineFragment.typographicBounds
                return (
                    x: point.x + tb.origin.x + charPos.x,
                    baselineY: point.y + tb.origin.y + charPos.y,
                    lineHeight: tb.height
                )
            }
        }
        return nil
    }

    /// Typographic bounds of the line fragment containing `localIndex`
    /// (index relative to the fragment, not the document).
    private func lineBounds(forLocalIndex localIndex: Int, point: CGPoint) -> CGRect? {
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let tb = lineFragment.typographicBounds
                return CGRect(x: point.x + lineFragment.glyphOrigin.x + tb.origin.x,
                              y: point.y + tb.origin.y,
                              width: tb.width,
                              height: tb.height)
            }
        }
        return nil
    }

    // MARK: - Code Block Background

    // Marc: code blocks are found by the `.codeBlockBackground` attribute. Upstream compared
    // `.backgroundColor` with `SyntaxHighlighter.backgroundColor()` (isCodeBlockBackgroundColor, removed).
    /// The code-block fill of this fragment, or nil outside code blocks.
    private var codeBlockBackground: NSColor? {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return nil }
        return ts.attribute(.codeBlockBackground, at: range.location, effectiveRange: nil) as? NSColor
    }

    private var hasCodeBlockBackground: Bool { codeBlockBackground != nil }

    // Marc: new helpers.
    private var configuration: MarkdownEditorConfiguration {
        (textLayoutManager?.textContainer?.textView as? NativeTextView)?.configuration ?? .default
    }

    private var codeBlockOutset: CGFloat { configuration.codeBlock.backgroundOutset }

    private var hasThematicBreak: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        var found = false
        ts.enumerateAttribute(.thematicBreak, in: range, options: []) { value, _, stop in
            if value as? Bool == true {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private var hasBlockquote: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        var found = false
        ts.enumerateAttribute(.blockquoteLevel, in: range, options: []) { value, _, stop in
            if value is Int {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private var hasTaskCheckbox: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        var found = false
        ts.enumerateAttribute(.taskCheckbox, in: range, options: []) { value, _, stop in
            if value is Bool {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func drawCodeBlockBackground(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        // Only fenced code-block fragments get the full-width fill (first char must carry the code background).
        guard let color = codeBlockBackground else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width

        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
           let lastLF = textLineFragments.last,
           lastLF.characterRange.length == 0 {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let rawY = point.y
        let rawMaxY = point.y + effectiveHeight
        // Marc: round, not floor/ceil: neighbouring lines then share one pixel edge
        // instead of overlapping by one, which a translucent fill shows as a seam.
        let snappedY = (rawY * scale).rounded() / scale
        let snappedMaxY = (rawMaxY * scale).rounded() / scale

        // Draw full-width background, clipping out any active selection rects
        // so the system's blue selection highlight remains visible inside code blocks.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let bgRect = CGRect( // Marc: plus the outset on each side
            x: point.x - layoutFragmentFrame.origin.x - codeBlockOutset,
            y: snappedY,
            width: containerWidth + 2 * codeBlockOutset,
            height: snappedMaxY - snappedY
        )

        // Marc: the block's first and last line round their outer corners.
        let opens = range.location == 0
            || ts.attribute(.codeBlockBackground, at: range.location - 1, effectiveRange: nil) == nil
        let closes = NSMaxRange(range) >= ts.length
            || ts.attribute(.codeBlockBackground, at: NSMaxRange(range), effectiveRange: nil) == nil
        let slab = roundedPath(bgRect, top: opens, bottom: closes)

        let selectionRects = selectionRectsInDrawCoordinates(drawPoint: point, snappedY: snappedY, snappedMaxY: snappedMaxY)
        color.setFill()
        if selectionRects.isEmpty {
            slab.fill()
        } else {
            let path = slab.copy() as! NSBezierPath
            path.windingRule = .evenOdd
            for r in selectionRects {
                path.appendRect(r.intersection(bgRect))
            }
            path.fill()
        }
    }

    /// Returns active text-selection rectangles intersecting this fragment, in
    /// the same draw-relative coordinate system used by `drawCodeBlockBackground`.
    private func selectionRectsInDrawCoordinates(drawPoint: CGPoint, snappedY: CGFloat, snappedMaxY: CGFloat) -> [CGRect] {
        guard let tlm = textLayoutManager else { return [] }
        var rects: [CGRect] = []

        let dx = drawPoint.x - layoutFragmentFrame.origin.x
        let myRange = self.rangeInElement

        for selection in tlm.textSelections {
            for textRange in selection.textRanges {
                let interStart = textRange.location.compare(myRange.location) == .orderedAscending
                    ? myRange.location : textRange.location
                let interEnd = textRange.endLocation.compare(myRange.endLocation) == .orderedDescending
                    ? myRange.endLocation : textRange.endLocation
                guard interStart.compare(interEnd) == .orderedAscending,
                      let intersection = NSTextRange(location: interStart, end: interEnd) else { continue }

                tlm.enumerateTextSegments(in: intersection, type: .selection, options: []) { _, segFrame, _, _ in
                    // Expand vertically to match the bgRect's snapped span so the
                    // even-odd cut-out is geometrically congruent with the fill.
                    let drawRect = CGRect(
                        x: segFrame.origin.x + dx,
                        y: snappedY,
                        width: segFrame.width,
                        height: snappedMaxY - snappedY
                    )
                    rects.append(drawRect)
                    return true
                }
            }
        }
        return rects
    }

    // Marc: new.
    /// Draw the language of a hidden opening fence at the right edge of the
    /// text column, vertically centered on the fence line.
    private func drawCodeBlockLanguage(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0,
              let language = ts.attribute(.codeBlockLanguage, at: range.location, effectiveRange: nil) as? String,
              let line = textLineFragments.first else { return }
        let theme = configuration.theme
        let codeFont = ts.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        let font = NSFont.monospacedSystemFont(ofSize: round(codeFont.pointSize * 0.85), weight: .regular)
        let label = NSAttributedString(string: language, attributes: [.font: font, .foregroundColor: theme.codeBlockLanguage])
        let size = label.size()
        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let tb = line.typographicBounds

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(
            x: point.x - layoutFragmentFrame.origin.x + containerWidth - size.width,
            y: point.y + tb.origin.y + (tb.height - size.height) / 2
        ))
    }

    // MARK: - Inline Code Pills

    // Marc: new section. Upstream filled inline code with `.backgroundColor` (glyph box).

    /// One rounded rect per line an `.inlineCodeBackground` run touches,
    /// sized to the code font's glyph box plus a little air.
    private func inlineCodePills(at point: CGPoint) -> [(rect: CGRect, color: NSColor)] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var pills: [(rect: CGRect, color: NSColor)] = []
        ts.enumerateAttribute(.inlineCodeBackground, in: range, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            // The content's font (not the tiny hidden backtick) sets the height.
            let contentIndex = min(attrRange.location + attrRange.length / 2, NSMaxRange(attrRange) - 1)
            let font = ts.attribute(.font, at: contentIndex, effectiveRange: nil) as? NSFont
                ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
            let local = NSRange(location: attrRange.location - range.location, length: attrRange.length)
            for lineFragment in textLineFragments {
                let lineRange = lineFragment.characterRange
                let hit = NSIntersectionRange(lineRange, local)
                guard hit.length > 0 else { continue }
                let tb = lineFragment.typographicBounds
                let start = lineFragment.locationForCharacter(at: hit.location)
                let reachesEnd = NSMaxRange(hit) >= NSMaxRange(lineRange)
                let endX = reachesEnd ? tb.width : lineFragment.locationForCharacter(at: NSMaxRange(hit)).x
                guard endX > start.x else { continue }
                let baseline = point.y + tb.origin.y + start.y
                let top = baseline - font.ascender - 2
                let bottom = baseline - font.descender + 1
                pills.append((
                    rect: CGRect(x: point.x + tb.origin.x + start.x, y: top, width: endX - start.x, height: bottom - top),
                    color: color
                ))
            }
        }
        return pills
    }

    private func drawInlineCodePills(at point: CGPoint, in context: CGContext) {
        let pills = inlineCodePills(at: point)
        guard !pills.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for pill in pills {
            pill.color.setFill()
            NSBezierPath(roundedRect: pill.rect, xRadius: 4, yRadius: 4).fill()
        }
    }

    // MARK: - Line-Box Backgrounds

    /// Fill rects for every `.markdownBlockBackground` run in this fragment,
    /// one per line the run touches, relative to `point`.
    ///
    /// Each rect spans the line fragment's full typographic bounds — the same
    /// box the blockquote bars use, which is why a run of them reads as one
    /// continuous shape. AppKit's own `.backgroundColor` fill is the glyph box
    /// instead (ascent + descent), so it falls short of the line height by the
    /// leading plus `paragraph.lineHeightExtraSpacing` and a wrapped highlight
    /// comes out as stacked bands.
    func blockBackgroundFills(at point: CGPoint) -> [(rect: CGRect, color: NSColor)] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var fills: [(rect: CGRect, color: NSColor)] = []
        ts.enumerateAttribute(.markdownBlockBackground, in: range, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let local = NSRange(location: attrRange.location - range.location, length: attrRange.length)
            for lineFragment in textLineFragments {
                let lineRange = lineFragment.characterRange
                let hit = NSIntersectionRange(lineRange, local)
                guard hit.length > 0 else { continue }
                let tb = lineFragment.typographicBounds
                let startX = lineFragment.locationForCharacter(at: hit.location).x
                // A run reaching the line's end fills to the line's own width:
                // the index one past the line belongs to the next fragment, and
                // asking this one for it is undefined.
                let reachesEnd = hit.location + hit.length >= lineRange.location + lineRange.length
                let endX = reachesEnd
                    ? tb.width
                    : lineFragment.locationForCharacter(at: hit.location + hit.length).x
                guard endX > startX else { continue }
                fills.append((
                    rect: CGRect(x: point.x + tb.origin.x + startX,
                                 y: point.y + tb.origin.y,
                                 width: endX - startX,
                                 height: tb.height),
                    color: color
                ))
            }
        }
        return fills
    }

    private func drawBlockBackgrounds(at point: CGPoint, in context: CGContext) {
        let fills = blockBackgroundFills(at: point)
        guard !fills.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        for fill in fills {
            fill.color.setFill()
            NSBezierPath(rect: fill.rect).fill()
        }
    }

    // MARK: - LaTeX / Block Image Helpers

    /// Compute the draw rect for a block image at `attrRange` using `point` as
    /// the draw origin.  Shared by `drawLatexImages` and `blockImageRects` so
    /// bounds and rendering stay in sync.
    private func blockImageDrawRect(
        attrRange: NSRange,
        imageBounds: CGRect,
        blockOffsetY: CGFloat?,
        point: CGPoint
    ) -> CGRect? {
        guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return nil }
        let fragLocation = fragmentNSRange?.location ?? 0
        let localStart = attrRange.location - fragLocation
        let localLast = max(localStart, localStart + attrRange.length - 1)
        let firstLb = lineBounds(forLocalIndex: localStart, point: point)
        // For a wrapped source span (e.g. a long `![alt](url)` that wraps in
        // a narrow window), anchor to the LAST line's maxY so the image
        // doesn't paint over subsequent wrapped lines of its own source.
        let lastLb = lineBounds(forLocalIndex: localLast, point: point) ?? firstLb
        let lineHeight = firstLb?.height ?? pos.lineHeight
        let firstLineMinY = firstLb?.origin.y ?? (pos.baselineY - lineHeight)
        let lastLineMaxY = (lastLb?.origin.y ?? firstLineMinY) + (lastLb?.height ?? lineHeight)

        let yPosition: CGFloat
        if let blockOffsetY {
            // Backward-compatible interpretation: `blockOffsetY` is the gap
            // from the FIRST line's top to the image's top (= baseLineHeight
            // + imageGap on a single-line source). Re-anchor to the last
            // line by subtracting one line height, leaving the same single-
            // line geometry intact while pushing the image down by one
            // extra line per wrap.
            yPosition = lastLineMaxY + blockOffsetY - lineHeight
        } else {
            yPosition = firstLineMinY + (lineHeight - imageBounds.height) / 2
        }
        return CGRect(x: pos.x, y: yPosition,
                       width: imageBounds.width, height: imageBounds.height)
    }

    /// Returns the rects of all block images in this fragment, relative to
    /// `point`.  Used by `renderingSurfaceBounds` (with `.zero`) to extend
    /// the surface so images drawn in paragraphSpacing aren't clipped.
    private func blockImageRects(at point: CGPoint) -> [CGRect] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var rects: [CGRect] = []
        ts.enumerateAttribute(.latexImage, in: range, options: []) { value, attrRange, _ in
            guard value is NSImage else { return }
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            guard isBlock else { return }
            // Skip overlay blocks; surface bounds must stay within container.
            if ts.attribute(.scrollableBlockNaturalWidth, at: attrRange.location, effectiveRange: nil) != nil {
                return
            }
            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.rectValue ?? .zero
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat
            if let rect = blockImageDrawRect(attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point) {
                rects.append(rect)
            }
        }
        return rects
    }

    // MARK: - LaTeX Images

    private func drawLatexImages(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        ts.enumerateAttribute(.latexImage, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, let image = value as? NSImage else { return }

            // Skip overlay-rendered blocks; WideTableOverlay owns the visual.
            if ts.attribute(.scrollableBlockNaturalWidth, at: attrRange.location, effectiveRange: nil) != nil {
                return
            }

            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.rectValue ?? CGRect(origin: .zero, size: image.size)
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat

            guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            let drawRect: CGRect
            if isBlock {
                guard let rect = blockImageDrawRect(attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point) else { return }
                drawRect = rect
            } else {
                let descent = imageBounds.origin.y
                drawRect = CGRect(x: pos.x,
                                  y: pos.baselineY + descent - imageBounds.height,
                                  width: imageBounds.width, height: imageBounds.height)
            }
            image.draw(in: drawRect)
        }
    }

    // MARK: - Thematic Breaks (---, ***, ___)

    /// One thematic-break line's decoration. `mark == nil` is the default
    /// rule and `rect` is the band to fill; otherwise `rect` is the box the
    /// mark string draws into, already centered in the text container.
    /// `rect` is what the reader sees: the rule's band, or the mark's INK box
    /// (not its layout box — see `ThematicBreakStyle.Mark`). `drawOrigin` is
    /// where the string is actually drawn to land that ink there.
    struct ThematicBreakDecoration {
        let rect: CGRect
        let mark: String?
        let font: NSFont
        let drawOrigin: CGPoint
    }

    /// Geometry for every thematic break in this fragment, in the same
    /// fragment-local space `draw(at:)` works in. Split out from the drawing so
    /// centering is assertable headlessly, the way `blockBackgroundFills(at:)`
    /// is — nothing here touches a graphics context.
    ///
    /// The rule spans the full container width regardless of how many source
    /// characters produced it, so a 3-char `---` matches an 80-char one. A mark
    /// is measured in the view's BASE font, not the run's: the run carries the
    /// hidden-marker styling that makes the source characters invisible.
    func thematicBreakDecorations(at point: CGPoint) -> [ThematicBreakDecoration] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var hasThematic = false
        ts.enumerateAttribute(.thematicBreak, in: range, options: []) { value, _, stop in
            if value as? Bool == true {
                hasThematic = true
                stop.pointee = true
            }
        }
        guard hasThematic else { return [] }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let textView = textLayoutManager?.textContainer?.textView
        let font = (textView as? NativeTextView)?.baseFont
            ?? textView?.font
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let containerX = point.x - layoutFragmentFrame.origin.x

        // Walk each line fragment in this layout fragment and decorate those
        // whose first character carries the marker. (HR tokens are always
        // single-line, but the loop is robust if a future caller ever stacks
        // several rules in one paragraph.)
        var out: [ThematicBreakDecoration] = []
        let fragLocation = range.location
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            let docStart = fragLocation + lr.location
            // TextKit 2 appends a synthetic trailing empty line fragment whose
            // characterRange lands at exactly `tsLen` — `attribute(at:)` needs
            // a strictly in-bounds index, so skip the sentinel.
            guard docStart < ts.length else { continue }
            guard ts.attribute(.thematicBreak, at: docStart, effectiveRange: nil) as? Bool == true else { continue }
            let tb = lineFragment.typographicBounds

            if let mark = ts.attribute(.thematicBreakMark, at: docStart, effectiveRange: nil) as? String,
               !mark.isEmpty {
                let scale = (ts.attribute(.thematicBreakMarkScale, at: docStart, effectiveRange: nil) as? CGFloat) ?? 1
                let markFont = scale == 1
                    ? font
                    : NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale) ?? font
                let attrs: [NSAttributedString.Key: Any] = [.font: markFont]
                let layoutSize = (mark as NSString).size(withAttributes: attrs)
                let lineCenterY = point.y + tb.origin.y + tb.height / 2

                // Ink bounds relative to the baseline, y up. Centering on this
                // rather than on the layout box is what keeps a high-drawn
                // glyph like `*` optically centered as the scale grows.
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: mark, attributes: attrs)
                )
                let ink = CTLineGetImageBounds(line, nil)
                let inkIsUsable = !ink.isNull && ink.height > 0

                // Flipped context: y grows downward, so ink that sits ABOVE the
                // baseline lands at `baseline - ink.maxY`.
                let baselineY = inkIsUsable
                    ? lineCenterY + ink.midY
                    : lineCenterY - layoutSize.height / 2 + markFont.ascender
                // Centered on ink horizontally too: a mark's advance width
                // includes side bearings that need not be symmetric, so
                // centering the layout box can leave the ink visibly off-axis.
                let layoutX = inkIsUsable
                    ? containerX + containerWidth / 2 - ink.midX
                    : containerX + (containerWidth - layoutSize.width) / 2
                let inkRect = CGRect(
                    x: inkIsUsable ? layoutX + ink.minX : layoutX,
                    y: inkIsUsable ? baselineY - ink.maxY : lineCenterY - layoutSize.height / 2,
                    width: inkIsUsable ? ink.width : layoutSize.width,
                    height: inkIsUsable ? ink.height : layoutSize.height
                )
                out.append(ThematicBreakDecoration(
                    rect: inkRect,
                    mark: mark,
                    font: markFont,
                    drawOrigin: CGPoint(x: layoutX, y: baselineY - markFont.ascender)
                ))
            } else {
                // tb.origin.y is already relative to this layout fragment.
                let centerY = point.y + tb.origin.y + tb.height / 2
                out.append(ThematicBreakDecoration(
                    rect: CGRect(x: containerX, y: centerY - 0.5, width: containerWidth, height: 1),
                    mark: nil,
                    font: font,
                    drawOrigin: CGPoint(x: containerX, y: centerY - 0.5)
                ))
            }
        }
        return out
    }

    /// Paint what `thematicBreakDecorations(at:)` worked out: a full-width rule,
    /// or the configured mark centered in the container.
    private func drawThematicBreaks(at point: CGPoint, in context: CGContext) {
        let decorations = thematicBreakDecorations(at: point)
        guard !decorations.isEmpty else { return }

        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let ruleColor = theme.rule ?? theme.strikethroughColor.withAlphaComponent(0.4) // Marc: theme.rule
        for decoration in decorations {
            guard let mark = decoration.mark else {
                ruleColor.setFill()
                NSBezierPath(rect: decoration.rect).fill()
                continue
            }
            // Ink, not a hairline: the rule colour is deliberately faint and
            // reads as a smudge on glyphs, so a mark takes the muted text
            // colour the blockquote bars and hidden markers already use.
            (mark as NSString).draw(
                at: decoration.drawOrigin,
                withAttributes: [.font: decoration.font, .foregroundColor: theme.mutedText]
            )
        }
    }

    // MARK: - Blockquote Panels

    // Marc: replaces upstream's drawBlockquoteBars. Bars sit at the level's left edge (upstream:
    // a quarter indent in) and use `theme.blockquoteBar`; the optional panel fill is new.

    /// What one quote line paints for one nesting level: the panel (nil
    /// without a theme background), the bar at its left edge, and which of
    /// the panel's right corners round.
    private struct QuotePanel {
        let rect: CGRect
        let bar: CGRect
        let roundTop: Bool
        let roundBottom: Bool
    }

    /// Every line carrying `.blockquoteLevel` paints one segment per level;
    /// stacked, the segments read as one panel with a continuous bar. The
    /// panel opening line reaches up into its padding (paragraph spacing
    /// before), the closing line down into the spacing after.
    private func blockquotePanels(at point: CGPoint) -> [QuotePanel] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        let config = configuration
        let padding = config.theme.blockquoteBackground == nil ? 0 : config.blockquote.panelPadding
        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let outset = config.codeBlock.backgroundOutset
        let leftEdge = point.x - layoutFragmentFrame.origin.x
        let indentPerLevel = Self.blockquoteIndentPerLevel
        // TextKit 2 appends a synthetic trailing empty line fragment whose
        // characterRange lands at exactly `tsLen` — skip it, it is no quote line.
        let lines = textLineFragments.filter {
            range.location + $0.characterRange.location < ts.length && $0.characterRange.length > 0
        }
        var panels: [QuotePanel] = []
        for (n, lineFragment) in lines.enumerated() {
            let docStart = range.location + lineFragment.characterRange.location
            guard let level = ts.attribute(.blockquoteLevel, at: docStart, effectiveRange: nil) as? Int else { continue }
            let edges = ts.attribute(.blockquoteEdges, at: docStart, effectiveRange: nil) as? [Int] ?? []
            let tb = lineFragment.typographicBounds
            for i in 0..<level {
                let edge = i < edges.count ? edges[i] : 0
                // Edges belong to the source line: only its first visual line
                // opens a panel and only its last one closes it.
                let opens = n == 0 && edge & BlockquoteEdge.top != 0
                let closes = n == lines.count - 1 && edge & BlockquoteEdge.bottom != 0
                // Only the outermost panel has padding; nested ones hug their lines.
                let pad = i == 0 ? padding : 0
                let top = point.y + tb.origin.y - (opens ? pad : 0)
                let bottom = point.y + tb.origin.y + tb.height + (closes ? pad : 0)
                // Marc: like a code block's fill, level 0 reaches `backgroundOutset` past the
                // text column on both sides, so its text stays on the text edge; level i sits
                // where level i's text (one indent less) starts.
                let x = i == 0 ? leftEdge - outset : leftEdge + CGFloat(i - 1) * indentPerLevel
                let right = leftEdge + containerWidth + outset
                panels.append(QuotePanel(
                    rect: CGRect(x: x, y: top, width: right - x, height: bottom - top),
                    bar: CGRect(x: x, y: top, width: Self.blockquoteBarWidth, height: bottom - top),
                    roundTop: opens,
                    roundBottom: closes
                ))
            }
        }
        return panels
    }

    private func drawBlockquotePanels(at point: CGPoint, in context: CGContext) {
        let panels = blockquotePanels(at: point)
        guard !panels.isEmpty else { return }
        let theme = configuration.theme

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        // Marc: only the outermost level has a panel (fully rounded, its bar clipped inside);
        // nested levels are bars. Upstream layered a panel per level.
        let isOuter = { (panel: QuotePanel) in panel.rect.minX < point.x - self.layoutFragmentFrame.origin.x }
        if let fill = theme.blockquoteBackground {
            fill.setFill()
            for panel in panels where isOuter(panel) {
                roundedPath(panel.rect, top: panel.roundTop, bottom: panel.roundBottom).fill()
            }
        }
        theme.blockquoteBar.setFill()
        for panel in panels {
            if isOuter(panel) {
                NSGraphicsContext.saveGraphicsState()
                roundedPath(panel.rect, top: panel.roundTop, bottom: panel.roundBottom).addClip()
                NSBezierPath(rect: panel.bar).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSBezierPath(rect: panel.bar).fill()
            }
        }
    }

    // Marc: new.
    /// `rect` with all four corners rounded on the sides where it opens (`top`) or closes (`bottom`).
    private func roundedPath(_ rect: CGRect, top: Bool, bottom: Bool) -> NSBezierPath {
        let r = min(Self.panelCornerRadius, rect.height / 2, rect.width / 2)
        guard top || bottom else { return NSBezierPath(rect: rect) }
        if top && bottom { return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r) }
        // Flipped context: minY is the top edge.
        let path = NSBezierPath()
        if top {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.appendArc(withCenter: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: 180, endAngle: 270)
            path.line(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.appendArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 270, endAngle: 0)
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.appendArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
            path.line(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.appendArc(withCenter: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: 90, endAngle: 180)
        }
        path.close()
        return path
    }

    // MARK: - Bullet Markers

    /// Paint a `•` over every hidden bullet marker (`.bulletMarker`). The
    /// glyph is drawn in the same font as the source so its baseline matches
    /// the surrounding text, and centered within the original marker char's
    /// advance so a `•` of a different width still sits where `-`/`*`/`+` was.
    private func drawBulletMarkers(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }
        let selectionRanges: [NSRange] = {
            guard let tv = textLayoutManager?.textContainer?.textView else { return [] }
            return tv.selectedRanges.map { $0.rangeValue }.filter { $0.length > 0 }
        }()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default
        let storageString = ts.string as NSString

        ts.enumerateAttribute(.bulletMarker, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, (value as? Bool) == true else { return }
            guard let pos = self.drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            let font = (ts.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont)
                ?? (self.textLayoutManager?.textContainer?.textView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
            // A `.bulletMarker` range means the styler painted the raw char
            // `.clear`, so something must ALWAYS be drawn over the slot. Outside
            // a selection that's the rendered `•`; while the marker sits inside
            // a selection the raw source char (`-`/`*`/`+`) is painted instead,
            // so selecting a list line reveals its raw syntax. (The styler's own
            // reveal is caret-based and doesn't fire for selections — an earlier
            // selection-skip here drew nothing over the cleared char, which left
            // an empty slot wherever the selection anchor wasn't in the marker.)
            let isSelected = selectionRanges.contains(where: { NSIntersectionRange($0, attrRange).length > 0 })
            let raw = storageString.substring(with: attrRange)
            let glyph = (isSelected ? raw : "•") as NSString
            let glyphAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.listMarker ?? theme.bodyText]

            let markerWidth = (raw as NSString).size(withAttributes: [.font: font]).width
            let glyphWidth = glyph.size(withAttributes: glyphAttrs).width
            let xOffset = max(0, (markerWidth - glyphWidth) / 2)
            // Flipped context: text origin is its top edge, baseline sits one
            // ascent below — so top = baseline − ascent aligns the glyph.
            let topY = pos.baselineY - font.ascender
            glyph.draw(at: CGPoint(x: pos.x + xOffset, y: topY), withAttributes: glyphAttrs)
        }
    }

    // MARK: - Ordered List Markers

    /// Paint the whole display marker "N." (`.orderedMarker` value) over the
    /// hidden source marker (digits + dot, cleared by the styler as one unit and
    /// kerned to the display width so any digit count aligns and content/wrapped
    /// lines hang at that width). A selection does not switch this back to the
    /// source digits: the number is positional, and swapping it under ⌘A made
    /// every item below an insertion read one lower than it renders.
    private func drawOrderedMarkers(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default

        ts.enumerateAttribute(.orderedMarker, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, let number = value as? String else { return }
            guard let pos = self.drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }
            // The view's base font, NOT the run's: the source marker carries the
            // near-zero hidden-marker font that keeps it invisible under a
            // selection, and drawing the number at 0.1pt would hide it too.
            let textView = self.textLayoutManager?.textContainer?.textView
            let font = (textView as? NativeTextView)?.baseFont
                ?? textView?.font
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let glyph = number as NSString
            let glyphAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.listMarker ?? theme.bodyText]
            let topY = pos.baselineY - font.ascender
            glyph.draw(at: CGPoint(x: pos.x, y: topY), withAttributes: glyphAttrs)
        }
    }

    // MARK: - Task List Checkboxes

    private func drawTaskCheckboxes(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        ts.enumerateAttribute(.taskCheckbox, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, value != nil else { return }
            // A `.taskCheckbox` range means the styler cleared the raw `- [ ]`
            // (and collapsed the box's advance), so the box must ALWAYS be
            // drawn — including while the range sits inside a selection. An
            // earlier selection-skip here left an empty marker-width gap (the
            // bullet-marker blank-slot bug's twin). Unlike bullets, the raw
            // source can't be painted here instead: the hidden `[ ]` advance
            // is collapsed, so raw glyphs would overlap the content — raw
            // reveal stays caret-based (taskRevealed in the styler).
            let isChecked = (value as? Bool) ?? false
            guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            // Box collapsed to 0.1pt, so pos.x sits at the content edge; the
            // square is right-aligned to it (shared with the click hit-test).
            // Use baseFont, NOT NSTextView.font — its getter returns the first
            // char's font (0.1pt in a heading-first doc → 1px boxes).
            let font = (textLayoutManager?.textContainer?.textView as? NativeTextView)?.baseFont
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let ascent = max(0, font.ascender)
            let descent = max(0, -font.descender)
            let size = TaskCheckboxGeometry.size(for: font)
            let boxX = TaskCheckboxGeometry.boxX(contentX: pos.x, size: size)
            let centerY = pos.baselineY + (descent - ascent) / 2
            let boxY = centerY - size / 2

            let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 2.0
            func alignToPixel(_ value: CGFloat) -> CGFloat {
                (value * scale).rounded(.toNearestOrAwayFromZero) / scale
            }
            let boxRect = CGRect(x: alignToPixel(boxX), y: alignToPixel(boxY), width: size, height: size)
            guard !boxRect.isEmpty, !boxRect.isNull else { return }

            let iconInset = max(0.0, size * 0.01)
            let iconRect = boxRect.insetBy(dx: iconInset, dy: iconInset)
            let configuration = (textLayoutManager?.textContainer?.textView as? NativeTextView)?.configuration
                ?? .default
            let style = configuration.taskCheckbox
            let symbolName = isChecked ? style.checkedSymbolName : style.uncheckedSymbolName
            let fallbackName = isChecked
                ? TaskCheckboxStyle.default.checkedSymbolName
                : TaskCheckboxStyle.default.uncheckedSymbolName
            if let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil) {
                let sizeConfig = NSImage.SymbolConfiguration(pointSize: iconRect.height, weight: .regular)
                let tint = isChecked ? configuration.theme.bodyText : configuration.theme.mutedText
                let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: tint)
                let symbolConfig = sizeConfig.applying(colorConfig)
                let symbol = baseSymbol.withSymbolConfiguration(symbolConfig) ?? baseSymbol
                symbol.draw(in: iconRect)
            }
        }
    }
}

// MARK: - Layout Manager Delegate

final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        PerfTrace.accumulate("fragProv") {
            makeFragment(textLayoutManager: textLayoutManager, textElement: textElement)
        }
    }

    private func makeFragment(
        textLayoutManager: NSTextLayoutManager,
        textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        // Seed body font + paragraphStyle so the trailing fragment doesn't inherit heading metrics (FB15131180).
        if let textView = textLayoutManager.textContainer?.textView as? NativeTextView {
            let baseFont = textView.baseFont
            let para = NSMutableParagraphStyle()
            let lineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: textView.layoutBridge)
            para.minimumLineHeight = ceil(lineHeight) + textView.configuration.paragraph.lineHeightExtraSpacing
            para.paragraphSpacing = ceil(lineHeight * textView.configuration.paragraph.spacingFactor)
            para.paragraphSpacingBefore = 0
            fragment.stExtraLineFragmentAttributes = NSDictionary(dictionary: [
                NSAttributedString.Key.font: baseFont,
                NSAttributedString.Key.foregroundColor: textView.configuration.theme.bodyText,
                NSAttributedString.Key.paragraphStyle: para
            ])
        }
        return fragment
    }
}
