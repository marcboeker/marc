import CoreGraphics

/// What the window's detail area shows. One per window (on EditorController), not per file, not saved.
enum PreviewMode: Equatable {
    /// The editor only.
    case editor
    /// The rendered preview in place of the editor (View > Preview, ⌃⌘P).
    case overlay
    /// Editor left, rendered preview right (View > Side by Side, ⌥⌘P).
    case split

    /// The mode after the key of `target` is pressed: the same key again goes back to the editor,
    /// the other mode's key switches directly.
    func toggled(_ target: PreviewMode) -> PreviewMode {
        self == target ? .editor : target
    }
}

/// Horizontal frames of the editor, the divider and the preview in a detail area `width` points wide.
struct PreviewLayout: Equatable {
    static let minimumSide: CGFloat = 280
    static let dividerWidth: CGFloat = 1
    /// Narrower than this, the split cannot give each side its minimum.
    static let minimumSplitWidth = 2 * minimumSide + dividerWidth

    var editorWidth: CGFloat
    var previewX: CGFloat
    var previewWidth: CGFloat

    /// `fraction` is the editor's part of the split (0.5 = 50/50). Each side keeps `minimumSide`
    /// while the width allows it; below that the two sides share the width equally.
    init(mode: PreviewMode, width: CGFloat, fraction: CGFloat) {
        switch mode {
        case .editor, .overlay:
            (editorWidth, previewX, previewWidth) = (width, 0, width)
        case .split:
            let content = max(width - Self.dividerWidth, 0)
            let editor = width < Self.minimumSplitWidth
                ? content / 2
                : min(max((content * fraction).rounded(), Self.minimumSide), content - Self.minimumSide)
            editorWidth = editor
            previewX = editor + Self.dividerWidth
            previewWidth = content - editor
        }
    }

    /// The fraction after the divider is dragged to `x`, kept so each side has `minimumSide`.
    static func fraction(dividerAt x: CGFloat, width: CGFloat) -> CGFloat {
        let content = width - dividerWidth
        guard width >= minimumSplitWidth, content > 0 else { return 0.5 }
        return min(max(x, minimumSide), content - minimumSide) / content
    }
}
