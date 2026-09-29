import SwiftUI

/// Sidebar with the document's headings. Click a heading to jump to it.
struct OutlineView: View {
    let controller: EditorController
    @State private var items: [OutlineItem] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if items.isEmpty {
                Text("No headings")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
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
                }
            }
        }
        .task(id: controller.text) {
            // Debounce: a newer edit cancels this task. The first load does not wait.
            if loaded { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            let text = controller.text
            let headings = await Task.detached { outline(of: text) }.value
            guard !Task.isCancelled else { return }
            loaded = true
            if headings != items { items = headings }
        }
    }
}
