import SwiftUI
import MarkdownEngine

struct ContentView: View {
    @Binding var document: MarcDocument
    let fileURL: URL?

    @State private var controller = EditorController()
    private var appearance = AppearanceSettings.shared
    /// Fixed for the window's life, so Save As does not reset the editor's undo history.
    /// Starts as the file URL string; unsaved documents get a UUID.
    @State private var documentId: String
    /// Every window opens with the outline sidebar hidden.
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    /// Width of the window's screen. The width limit is a part of it.
    @State private var screenWidth = NSScreen.main?.frame.width ?? 0

    init(document: Binding<MarcDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        _documentId = State(initialValue: fileURL?.absoluteString ?? UUID().uuidString)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            OutlineView(controller: controller)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
        } detail: {
            GeometryReader { geometry in
                NativeTextViewWrapper(
                    text: $document.text,
                    configuration: configuration(width: geometry.size.width),
                    fontName: appearance.fontName,
                    fontSize: appearance.fontSize,
                    documentId: documentId,
                    onTextViewReady: {
                        controller.attach($0)
                        updateScreenWidth()
                    },
                    onWillPaste: { controller.dropPaste.willPaste(in: $0, pasteboard: $1) },
                    onDropFiles: { controller.dropPaste.drop(in: $0, info: $1, insertionIndex: $2) },
                    onSaveRequest: { _ in controller.saveRequested() }
                )
            }
            .overlay(alignment: .bottom) {
                if let notice = controller.mergeNotice {
                    MergeNoticeView(
                        notice: notice,
                        onClick: {
                            controller.selectFirstConflict()
                            controller.mergeNotice = nil
                        },
                        onTimeout: {
                            if controller.mergeNotice == notice { controller.mergeNotice = nil }
                        }
                    )
                    .padding(.bottom, 20)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: controller.mergeNotice)
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowFrameRestorer())
        .focusedSceneValue(\.editorController, controller)
        .onAppear { sync() }
        .onDisappear { controller.reloader.stop() }
        .onChange(of: fileURL) {
            sync()
            controller.lint.refresh()   // relative link targets resolve against the new folder
        }
        .onChange(of: document.text) { controller.text = document.text }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            if note.object as? NSWindow === controller.textView?.window { updateScreenWidth() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateScreenWidth()
        }
    }

    private func sync() {
        controller.fileURL = fileURL
        controller.text = document.text
        controller.reloader.watch(fileURL, text: document.text)
    }

    private func updateScreenWidth() {
        if let screen = controller.textView?.window?.screen ?? NSScreen.main {
            screenWidth = screen.frame.width
        }
    }

    /// `width` is the editor width; with a width limit the horizontal inset centers the text.
    private func configuration(width: CGFloat) -> MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration()
        config.services.images = FileImageProvider(baseURL: fileURL?.deletingLastPathComponent())
        config.extensions = [StrikethroughExtension()]
        config.theme = .marc
        // Code lines up with the body text; the slab reaches into the inset instead.
        config.codeBlock.horizontalIndent = 0
        config.codeBlock.backgroundOutset = 12
        config.lists.autoClosePairsEnabled = false
        config.spellChecking.automaticQuoteSubstitution = false
        config.textInsets = TextInsets(
            horizontal: appearance.horizontalInset(forWidth: width, screenWidth: screenWidth, minimum: 24),
            vertical: 16
        )
        config.paragraph.lineHeightExtraSpacing = appearance.lineSpacing
        // A fixed ~2-line slack below the last line; the engine default (25% of the viewport) leaves half a window empty.
        config.overscroll = OverscrollPolicy(percent: 0, maxPoints: 48, minPoints: 48)
        return config
    }
}
