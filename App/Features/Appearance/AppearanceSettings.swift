import AppKit
import SwiftUI

/// Editor font, font size, line spacing and line width. Shared by all windows, saved in UserDefaults.
@MainActor
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    static let systemFamily = "System"
    static let defaultFontSize: CGFloat = 15
    static let fontSizeRange: ClosedRange<CGFloat> = 10...32
    static let defaultLineSpacing: CGFloat = 2
    /// Characters per line: the 65–75 that read best, with room for a mono font's wider letters.
    static let defaultLineWidth = 72
    static let lineWidthRange: ClosedRange<Int> = 40...140

    private enum Key {
        static let fontFamily = "editorFontFamily"
        static let fontSize = "editorFontSize"
        static let lineSpacing = "editorLineSpacing"
        static let lineWidth = "editorLineWidth"
        static let limitsLineWidth = "editorLimitsLineWidth"
        static let showsMarkdownSource = "editorShowsMarkdownSource"
    }

    /// Font family name, or `systemFamily` for the system font.
    var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: Key.fontFamily) }
    }
    /// Body text size in points. Headings scale from it.
    var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: Key.fontSize) }
    }
    /// Extra points added to each line's height.
    var lineSpacing: CGFloat {
        didSet { UserDefaults.standard.set(Double(lineSpacing), forKey: Key.lineSpacing) }
    }
    /// Longest line in characters (widths of "0") when `limitsLineWidth` is on. The column is centered.
    var lineWidth: Int {
        didSet { UserDefaults.standard.set(lineWidth, forKey: Key.lineWidth) }
    }
    /// Off: the text uses the full width of the window.
    var limitsLineWidth: Bool {
        didSet { UserDefaults.standard.set(limitsLineWidth, forKey: Key.limitsLineWidth) }
    }
    /// View > Show Markdown Source: all syntax visible, one font size, light highlighting.
    /// Not part of `reset()`: it is a view mode, not a look.
    var showsMarkdownSource: Bool {
        didSet { UserDefaults.standard.set(showsMarkdownSource, forKey: Key.showsMarkdownSource) }
    }

    private init() {
        let defaults = UserDefaults.standard
        // A saved family that is no longer installed falls back to the system font.
        let saved = defaults.string(forKey: Key.fontFamily)
        fontFamily = saved.flatMap { NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil ? $0 : nil }
            ?? Self.systemFamily
        fontSize = (defaults.object(forKey: Key.fontSize) as? Double)
            .map { min(max(CGFloat($0), Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound) }
            ?? Self.defaultFontSize
        lineSpacing = (defaults.object(forKey: Key.lineSpacing) as? Double).map { CGFloat($0) }
            ?? Self.defaultLineSpacing
        lineWidth = (defaults.object(forKey: Key.lineWidth) as? Int)
            .map { min(max($0, Self.lineWidthRange.lowerBound), Self.lineWidthRange.upperBound) }
            ?? Self.defaultLineWidth
        limitsLineWidth = defaults.object(forKey: Key.limitsLineWidth) as? Bool ?? true
        showsMarkdownSource = defaults.bool(forKey: Key.showsMarkdownSource)
    }

    /// Name for `NSFont(name:size:)`. The engine falls back to the system font for unknown names.
    var fontName: String {
        guard fontFamily != Self.systemFamily,
              let font = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: fontSize)
        else { return "SF Pro" }
        return font.fontName
    }

    /// Family name for the HTML of Print and Preview, or nil for the system font.
    var htmlFontFamily: String? { fontFamily == Self.systemFamily ? nil : fontFamily }

    /// One point up or down, kept in `fontSizeRange`.
    func stepFontSize(by points: CGFloat) {
        fontSize = min(max(fontSize + points, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    func reset() {
        fontFamily = Self.systemFamily
        fontSize = Self.defaultFontSize
        lineSpacing = Self.defaultLineSpacing
        lineWidth = Self.defaultLineWidth
        limitsLineWidth = true
    }

    /// Horizontal text inset that centers a column of `columnWidth` points (nil: full width) in an
    /// editor `width` points wide. Never less than `minimum`.
    nonisolated static func horizontalInset(forWidth width: CGFloat, columnWidth: CGFloat?, minimum: CGFloat) -> CGFloat {
        guard let columnWidth else { return minimum }
        return max(minimum, ((width - columnWidth) / 2).rounded())
    }
}

/// App > Settings… (⌘,). Changes apply live to all open editors.
struct AppearanceSettingsView: View {
    @Bindable var settings = AppearanceSettings.shared

    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Picker("Font:", selection: $settings.fontFamily) {
                Text(AppearanceSettings.systemFamily).tag(AppearanceSettings.systemFamily)
                Divider()
                ForEach(families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            LabeledContent("Font size:") {
                HStack {
                    Slider(value: $settings.fontSize, in: AppearanceSettings.fontSizeRange, step: 1)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            LabeledContent("Line spacing:") {
                HStack {
                    Slider(value: $settings.lineSpacing, in: 0...24, step: 1)
                    Text("\(Int(settings.lineSpacing)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            LabeledContent("Line width:") {
                VStack(alignment: .leading) {
                    HStack {
                        Slider(value: Binding(get: { Double(settings.lineWidth) }, set: { settings.lineWidth = Int($0) }),
                               in: Double(AppearanceSettings.lineWidthRange.lowerBound)...Double(AppearanceSettings.lineWidthRange.upperBound),
                               step: 4)
                        Text("\(settings.lineWidth) characters")
                            .monospacedDigit()
                            .frame(width: 96, alignment: .trailing)
                    }
                    .disabled(!settings.limitsLineWidth)
                    Toggle("Limit the line width", isOn: $settings.limitsLineWidth)
                }
            }
            HStack {
                Spacer()
                Button("Reset") { settings.reset() }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
