import AppKit
import SwiftUI

/// The rendered preview, with the find bar while the preview replaces the editor.
struct PreviewPane: View {
    let preview: PreviewController
    let text: String
    let folder: URL?
    let style: DocumentStyle

    var body: some View {
        VStack(spacing: 0) {
            if preview.isFinding {
                PreviewFindBar(preview: preview)
                Divider()
            }
            PreviewWebView(preview: preview, text: text, folder: folder, style: style)
        }
    }
}

/// Hosts the controller's one web view. The view outlives this wrapper, so a container holds it.
private struct PreviewWebView: NSViewRepresentable {
    let preview: PreviewController
    let text: String
    let folder: URL?
    let style: DocumentStyle

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = preview.webView
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        preview.refresh(text: text, folder: folder, style: style)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        preview.refresh(text: text, folder: folder, style: style)
    }
}

/// Edit > Find for the rendered text: Return finds the next match, ⇧Return the one before, Esc closes.
private struct PreviewFindBar: View {
    @Bindable var preview: PreviewController
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $preview.findText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(maxWidth: 260)
                .onSubmit { preview.find(backwards: NSEvent.modifierFlags.contains(.shift)) }
                .onChange(of: preview.findText) { preview.findFromTop() }
            if preview.findFailed {
                Text("Not found")
                    .foregroundStyle(.secondary)
            }
            ControlGroup {
                Button { preview.find(backwards: true) } label: { Image(systemName: "chevron.left") }
                    .help("Find Previous")
                Button { preview.find(backwards: false) } label: { Image(systemName: "chevron.right") }
                    .help("Find Next")
            }
            .fixedSize()
            .disabled(preview.findText.isEmpty)
            Spacer()
            Button("Done") { preview.closeFind() }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onExitCommand { preview.closeFind() }
        .onAppear { focused = true }
    }
}

/// The line between editor and preview. Drag it to change the split.
struct SplitDivider: View {
    let width: CGFloat
    @Binding var fraction: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: PreviewLayout.dividerWidth)
            .overlay {
                // A wider grab area than the line.
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(DragGesture(coordinateSpace: .named(Self.space)).onChanged { drag in
                        fraction = PreviewLayout.fraction(dividerAt: drag.location.x, width: width)
                    })
            }
    }

    /// The detail area, which the drag location is in.
    static let space = "previewSplit"
}
