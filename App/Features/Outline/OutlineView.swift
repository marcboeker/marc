import SwiftUI

/// Sidebar section with the shown file's headings. Click a heading to jump to it.
struct OutlineSection: View {
    let controller: EditorController
    let file: MarcdownFile

    var body: some View {
        Section("Outline") {
            if file.outline.isEmpty {
                Text("No headings")
                    .foregroundStyle(.tertiary)
                    .selectionDisabled()
            } else {
                ForEach(file.outline) { item in
                    Button {
                        controller.setSelectedRange(NSRange(location: item.range.location, length: 0))
                    } label: {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .lineLimit(1)
                            .padding(.leading, CGFloat(item.level - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .selectionDisabled()
                }
            }
        }
    }
}

