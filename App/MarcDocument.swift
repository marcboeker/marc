import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared as imported in Resources/Info.plist.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown file. The editor writes `text` back through the binding on every edit.
struct MarcDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
