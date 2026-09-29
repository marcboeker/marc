// Marc: process-wide switches for constructs the engine parses by default.
// Defaults keep upstream behavior; Marc turns them off once at launch, before
// any editor exists. Parse caches are not keyed on these, so never flip them
// while an editor is alive.

import Foundation

public enum MarkdownEngineFeatures {
    /// `[[wiki links]]`, including the storage/display `|id` transform.
    nonisolated(unsafe) public static var wikiLinks = true
    /// `![[image embeds]]`.
    nonisolated(unsafe) public static var imageEmbeds = true
    /// `$inline$` and `$$block$$` LaTeX.
    nonisolated(unsafe) public static var latex = true
    /// Typing `->` rewrites it to the arrow character.
    nonisolated(unsafe) public static var arrowSubstitution = true

    /// Turn off everything that is not plain GFM.
    public static func disableNonGFM() {
        wikiLinks = false
        imageEmbeds = false
        latex = false
        arrowSubstitution = false
    }
}
