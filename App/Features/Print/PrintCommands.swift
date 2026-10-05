import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File > Page Setup…, Export as PDF…, Print… (⌘P). Replaces the system items, which print the
/// editor view itself (screen colours, window width, hidden syntax).
struct PrintCommands: Commands {
    @FocusedValue(\.editorController) private var controller

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { NSApp.runPageLayout(nil) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Export as PDF…") { controller?.exportPDF() }
                .disabled(controller == nil)
            Button("Print…") { controller?.startPrintJob(.printPanel) }
                .keyboardShortcut("p")
                .disabled(controller == nil)
        }
    }
}

extension EditorController {
    /// Ask for a file name next to the document, then write the PDF.
    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = documentTitle + ".pdf"
        if let documentFolder { panel.directoryURL = documentFolder }
        let save = { [weak self] (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            // Next turn: the sheet must be gone before the print operation attaches its own.
            DispatchQueue.main.async { self?.startPrintJob(.pdf(url)) }
        }
        if let window = textView?.window {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
        }
    }

    private var documentTitle: String { file?.title ?? "Untitled" }

    func startPrintJob(_ output: PrintJob.Output) {
        let title = documentTitle
        let html = PrintRenderer.page(
            markdown: currentText,
            title: title,
            baseFolder: documentFolder,
            fontFamily: AppearanceSettings.shared.htmlFontFamily
        )
        PrintJob.start(html: html, title: title, output: output, window: textView?.window)
    }
}
