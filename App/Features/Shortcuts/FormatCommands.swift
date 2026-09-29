import SwiftUI
import AppKit

/// One entry of the Format menu.
enum FormatCommand: Hashable {
    case heading(Int)
    case paragraph
    case bold, italic, strikethrough, code
    case link
    case quote, bullet, numbered, task
    case codeBlock
    case rule

    var title: String {
        switch self {
        case .heading(let level): "Heading \(level)"
        case .paragraph: "Paragraph"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        case .link: "Link"
        case .quote: "Quote"
        case .bullet: "Bulleted List"
        case .numbered: "Numbered List"
        case .task: "Task List"
        case .codeBlock: "Code Block"
        case .rule: "Horizontal Rule"
        }
    }

    var shortcut: (key: KeyEquivalent, modifiers: EventModifiers) {
        switch self {
        case .heading(let level): (KeyEquivalent(Character("\(level)")), .command)
        case .paragraph: ("0", .command)
        case .bold: ("b", .command)
        case .italic: ("i", .command)
        case .strikethrough: ("x", [.command, .shift])
        case .code: ("e", .command)
        case .link: ("k", .command)
        case .quote: ("'", .command)
        case .bullet: ("8", [.command, .shift])
        case .numbered: ("7", [.command, .shift])
        case .task: ("t", [.command, .shift])
        case .codeBlock: ("c", [.command, .shift])
        case .rule: ("-", [.command, .shift])
        }
    }

    func perform(on edit: TextEdit, pasteboardURL: String?) -> TextEdit {
        switch self {
        case .heading(let level): MarkdownEdits.line(.heading(level), edit)
        case .paragraph: MarkdownEdits.line(.paragraph, edit)
        case .bold: MarkdownEdits.inline("**", edit)
        case .italic: MarkdownEdits.inline("*", edit)
        case .strikethrough: MarkdownEdits.inline("~~", edit)
        case .code: MarkdownEdits.inline("`", edit)
        case .link: MarkdownEdits.link(edit, url: pasteboardURL)
        case .quote: MarkdownEdits.line(.quote, edit)
        case .bullet: MarkdownEdits.line(.bullet, edit)
        case .numbered: MarkdownEdits.line(.numbered, edit)
        case .task: MarkdownEdits.line(.task, edit)
        case .codeBlock: MarkdownEdits.codeBlock(edit)
        case .rule: MarkdownEdits.rule(edit)
        }
    }
}

extension EditorController {
    /// Apply a Format command as one undo step, replacing only the changed range.
    func apply(_ command: FormatCommand) {
        guard let textView else { return }
        let old = TextEdit(text: textView.string, selection: textView.selectedRange())
        let result = command.perform(on: old, pasteboardURL: command == .link ? Self.pasteboardURL() : nil)
        if let change = MarkdownEdits.replacement(from: old.text, to: result.text) {
            replace(change.range, with: change.text, actionName: command.title)
        }
        setSelectedRange(result.selection)
    }

    /// A single web or mail URL on the general pasteboard, else nil.
    private static func pasteboardURL() -> String? {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, !string.contains(where: \.isWhitespace),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else { return nil }
        return string
    }
}

/// The "Format" menu.
struct FormatCommands: Commands {
    @FocusedValue(\.editorController) private var controller

    var body: some Commands {
        CommandMenu("Format") {
            ForEach(1...6, id: \.self) { item(.heading($0)) }
            item(.paragraph)
            Divider()
            item(.bold)
            item(.italic)
            item(.strikethrough)
            item(.code)
            item(.link)
            Divider()
            item(.quote)
            item(.bullet)
            item(.numbered)
            item(.task)
            Divider()
            item(.codeBlock)
            item(.rule)
        }
    }

    private func item(_ command: FormatCommand) -> some View {
        Button(command.title) { controller?.apply(command) }
            .keyboardShortcut(command.shortcut.key, modifiers: command.shortcut.modifiers)
            .disabled(controller == nil)
    }
}
