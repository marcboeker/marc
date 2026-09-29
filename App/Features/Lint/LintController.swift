import AppKit

/// Installed on the text view when the engine has created it. Lints the text
/// after typing pauses and shows the issues as gutter icons.
@MainActor
final class LintController {
    private unowned let controller: EditorController
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private let gutter = LintGutter()

    /// Quiet time after the last edit before linting.
    private static let debounce: Duration = .milliseconds(400)

    init(controller: EditorController) {
        self.controller = controller
    }

    func install(on textView: NSTextView) {
        gutter.attach(to: textView)
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.textDidChange() }
        }
        textDidChange()
    }

    /// Lint again without an edit, e.g. after Save As moved the document to another folder.
    func refresh() { textDidChange() }

    private func textDidChange() {
        pending?.cancel()
        // A newer edit cancels this task, during the sleep or while the lint runs.
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            let text = controller.currentText, folder = controller.documentFolder
            let issues = await Task.detached { Marc.lint(text, documentFolder: folder) }.value
            guard !Task.isCancelled else { return }
            gutter.show(issues)
        }
    }
}
