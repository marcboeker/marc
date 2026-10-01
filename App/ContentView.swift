import SwiftUI
import MarkdownEngine

struct ContentView: View {
    @State private var controller = EditorController()
    private var files = OpenFiles.shared
    private var appearance = AppearanceSettings.shared
    /// Opens when the file count goes from one or none to more than one (or the window opens with several files);
    /// it never closes by itself, so a ⌃⌘S hide holds until the count drops to one and goes up again.
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    /// Width of the window's screen. The width limit is a part of it.
    @State private var screenWidth = NSScreen.main?.frame.width ?? 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(controller: controller)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
        } detail: {
            if let file = files.selected {
                editor(file)
            } else {
                emptyState
            }
        }
        .navigationTitle(title)
        .frame(minWidth: 480, minHeight: 320)
        .background(MainWindowAccessor())
        .focusedSceneValue(\.editorController, files.selected == nil ? nil : controller)
        .onAppear {
            files.editor = controller
            sync()
        }
        .onChange(of: files.files.count, initial: true) { old, new in
            if new > 1, old <= 1 || old == new { columnVisibility = .all }
        }
        .onChange(of: files.selectedID) { sync() }
        .onChange(of: files.selected?.url, initial: true) {   // a switch, Save As, Move To
            files.window?.representedURL = files.selected?.url
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            if note.object as? NSWindow === controller.textView?.window { updateScreenWidth() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateScreenWidth()
        }
    }

    /// One editor for all files. Each file has its own `documentId` and text binding, so the engine
    /// keeps undo and scroll position per file, and an edit lands in the file it was made in.
    private func editor(_ file: MarcFile) -> some View {
        GeometryReader { geometry in
            NativeTextViewWrapper(
                text: Binding(get: { file.text }, set: { file.edit($0) }),
                configuration: configuration(width: geometry.size.width, folder: file.url?.deletingLastPathComponent()),
                fontName: appearance.fontName,
                fontSize: appearance.fontSize,
                documentId: file.id.uuidString,
                retainedScrollDocumentIds: Set(files.files.map(\.id.uuidString)),   // closed files drop their undo
                onTextViewReady: {
                    controller.attach($0)
                    updateScreenWidth()
                },
                onWillPaste: { controller.dropPaste.willPaste(in: $0, pasteboard: $1) },
                onDropFiles: { controller.dropPaste.drop(in: $0, info: $1, insertionIndex: $2) },
                onSaveRequest: { _ in controller.saveRequested() },
                onDocumentShown: { _ in controller.fileShown(file) }
            )
        }
        .overlay(alignment: .bottom) {
            if let notice = file.mergeNotice {
                MergeNoticeView(
                    notice: notice,
                    onClick: {
                        controller.selectFirstConflict()
                        file.mergeNotice = nil
                    },
                    onTimeout: {
                        if file.mergeNotice == notice { file.mergeNotice = nil }
                    }
                )
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: file.mergeNotice)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No File Open")
                .font(.title3)
            Text("Press ⌘O to open a file or ⌘N to start a new one.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String { files.selected?.title ?? "Marc" }

    /// Point the editor controller at the selected file. The engine shows it a turn later (`fileShown`).
    private func sync() {
        controller.file = files.selected
        controller.lint.clear()
    }

    private func updateScreenWidth() {
        if let screen = controller.textView?.window?.screen ?? NSScreen.main {
            screenWidth = screen.frame.width
        }
    }

    /// `width` is the editor width; `folder` resolves relative images; with a width limit the horizontal inset centers the text.
    private func configuration(width: CGFloat, folder: URL?) -> MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration()
        config.services.images = FileImageProvider(baseURL: folder)
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
