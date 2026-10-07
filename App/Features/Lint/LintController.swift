import AppKit
import Observation

/// Installed on the text view when the engine has created it. Shows the shown file's lint issues
/// (`MarcdownFile.lintIssues`, kept up to date by the file) as gutter icons.
@MainActor
final class LintController {
    private let gutter = LintGutter()
    /// Bumped by `show` and `clear`, so the observation of a file no longer shown stops.
    private var generation = 0

    func install(on textView: NSTextView) {
        gutter.attach(to: textView)
    }

    /// The editor shows another file: drop the old marks now; `show(_:)` brings the file's own.
    func clear() {
        generation &+= 1
        gutter.show([])
    }

    /// The editor shows `file` (its text is in the text view): show its issues, and again each time they change.
    func show(_ file: MarcdownFile) {
        generation &+= 1
        track(file, generation: generation)
    }

    private func track(_ file: MarcdownFile, generation: Int) {
        guard generation == self.generation else { return }
        let issues = withObservationTracking { file.lintIssues } onChange: { [weak self] in
            // Called before the change; read the new value a turn later.
            DispatchQueue.main.async { self?.track(file, generation: generation) }
        }
        gutter.show(issues)
    }
}
