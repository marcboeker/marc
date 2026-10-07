import AppKit
import Testing
@testable import MarkdownEngine
@testable import Marcdown

/// The editor and the pages take their measures from one DocumentStyle: these check that both
/// sides end at the same numbers.
struct DocumentStyleTests {
    private let style = DocumentStyle(fontFamily: "Menlo", fontSize: 19, lineSpacing: 0, lineWidth: 72)

    private var config: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration()
        style.apply(to: &config)
        return config
    }

    @Test func lineHeightIsTheSameInEditorAndPage() {
        #expect(style.naturalLineHeight + config.paragraph.lineHeightExtraSpacing == style.lineHeight)
        #expect(config.lists.extraLineHeight == config.paragraph.lineHeightExtraSpacing)
        #expect(style.css(unit: "px").contains("p, li, blockquote, dt, dd, summary { line-height: \(Int(style.lineHeight))px; }"))
    }

    @Test func blankLineIsTheBlockGap() {
        #expect(config.paragraph.blankLineHeight == style.gap)
        #expect(config.paragraph.spacingFactor == 0)
        #expect(style.css(unit: "px").contains("margin: 0 0 \(Int(style.gap))px;"))
    }

    @Test func headingSpaceAboveAddsUpToTheSameValue() {
        for level in 1...6 {
            let above = config.headings.topSpacingEm(for: level) * style.headingSize(level) + style.gap
            #expect(abs(above - style.headingAbove) < 0.5)
        }
        #expect(style.css(unit: "px").contains("h1 { font-size: \(Int(style.headingSize(1)))px; }"))
    }

    @Test func listTextStartsAtTheListIndent() {
        #expect(abs(style.markerIndent + style.width("- ") - style.listIndent) < 0.5)
        #expect(style.css(unit: "px").contains("ul, ol { padding-left: \(Int(style.listIndent))px; }"))
    }

    @Test func panelsReachIntoTheInsetByTheSameOutset() {
        #expect(config.codeBlock.backgroundOutset == style.outset)
        #expect(style.css(unit: "px").contains("margin-left: -\(Int(style.outset))px;"))
    }

    @Test func lineWidthIsCountedInCharacters() {
        #expect(style.columnWidth == (72 * style.width("0")).rounded())
        #expect(DocumentStyle(fontFamily: nil, fontSize: 15, lineSpacing: 2, lineWidth: nil).columnWidth == nil)
    }

    @Test func insetCentersTheColumn() {
        #expect(AppearanceSettings.horizontalInset(forWidth: 1000, columnWidth: 600, minimum: 24) == 200)
        #expect(AppearanceSettings.horizontalInset(forWidth: 500, columnWidth: 600, minimum: 24) == 24)
        #expect(AppearanceSettings.horizontalInset(forWidth: 1000, columnWidth: nil, minimum: 24) == 24)
    }

    @Test func paletteGivesBothAppearances() {
        #expect(DocumentPalette.cssVariables(dark: false).contains("--text: rgba(29, 29, 31, 1);"))
        #expect(DocumentPalette.cssVariables(dark: true).contains("--text: rgba(255, 255, 255, 0.87);"))
        let dark = NSAppearance(named: .darkAqua)!
        var resolved: NSColor?
        dark.performAsCurrentDrawingAppearance { resolved = DocumentPalette.text.color.usingColorSpace(.sRGB) }
        #expect(resolved?.alphaComponent == 0.87)
    }

    @Test func codeBlocksCarryTheirLanguage() {
        #expect(MarkdownHTML.render("```swift\nlet a = 1\n```\n").contains(#"<pre data-lang="swift"><code class="language-swift">"#))
        #expect(MarkdownHTML.labelLanguages("<pre><code>x</code></pre>") == "<pre><code>x</code></pre>")
    }

    @Test func pageWrapsLongWordsAndThemesMark() {
        let css = style.css(unit: "px")
        #expect(css.contains("overflow-wrap: break-word"))
        #expect(css.contains("mark { background: var(--mark);"))
    }
}
