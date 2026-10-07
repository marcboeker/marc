import SwiftUI
import MarkdownEngine

struct ContentView: View {
    @State private var controller = EditorController()
    private var files = OpenFiles.shared
    private var appearance = AppearanceSettings.shared
    /// Opens when `OpenFiles.opensSidebar` turns true: the file count goes from one or none to more than one, or a pin
    /// appears (also when the window opens with several files or pins). It never closes by itself, so a ⌃⌘S hide
    /// holds until that turns false and true again.
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    /// The editor's part of the split. Not saved: each Side by Side starts at 50/50.
    @State private var splitFraction: CGFloat = 0.5
    @State private var detailWidth: CGFloat = 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(controller: controller)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
        } detail: {
            if let file = files.selected {
                detail(file)
            } else {
                emptyState
            }
        }
        .navigationTitle(title)
        // Side by side: the window does not get narrower than the split needs (the sidebar goes first).
        .frame(minWidth: controller.previewMode == .split ? max(480, PreviewLayout.minimumSplitWidth) : 480, minHeight: 320)
        .background(MainWindowAccessor())
        .overlay(alignment: .bottom) {
            if let notice = files.missingPinNotice {
                NoticeCapsule(message: notice.message, id: notice.id, seconds: 4) {
                    if files.missingPinNotice == notice { files.missingPinNotice = nil }
                }
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: files.missingPinNotice)
        .overlay(alignment: .top) { LauncherOverlay() }   // ⇧⌘P
        .focusedSceneValue(\.editorController, files.selected == nil ? nil : controller)
        .onAppear {
            files.editor = controller
            sync()
        }
        .onChange(of: files.opensSidebar, initial: true) { _, opens in
            if opens { columnVisibility = .all }
        }
        .onChange(of: files.selectedID) { sync() }
        .onChange(of: controller.previewMode) { _, mode in
            if mode == .split {
                splitFraction = 0.5
                makeRoomForSplit()
            }
        }
        .onChange(of: files.selected?.url, initial: true) {   // a switch, Save As, Move To
            files.window?.representedURL = files.selected?.url
        }
    }

    /// The editor, and in a preview mode the rendered page over it or beside it. The editor stays in
    /// the view tree in every mode (hidden under the overlay), so it keeps its text view, undo and scroll.
    private func detail(_ file: MarcdownFile) -> some View {
        GeometryReader { geometry in
            let mode = controller.previewMode
            let layout = PreviewLayout(mode: mode, width: geometry.size.width, fraction: splitFraction)
            ZStack(alignment: .topLeading) {
                editor(file, width: layout.editorWidth)
                    .frame(width: layout.editorWidth, height: geometry.size.height)
                    .opacity(mode == .overlay ? 0 : 1)
                    .allowsHitTesting(mode != .overlay)
                    .accessibilityHidden(mode == .overlay)
                if mode == .split {
                    SplitDivider(width: geometry.size.width, fraction: $splitFraction)
                        .frame(height: geometry.size.height)
                        .offset(x: layout.editorWidth)
                }
                if mode != .editor {
                    PreviewPane(
                        preview: controller.preview,
                        text: file.text,
                        folder: file.url?.deletingLastPathComponent(),
                        style: DocumentStyle(settings: appearance)
                    )
                    .frame(width: layout.previewWidth, height: geometry.size.height)
                    .offset(x: layout.previewX)
                }
            }
            .coordinateSpace(.named(SplitDivider.space))
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            detailWidth = width
            // Narrower than the split needs (the window shrank, or the sidebar opened): the sidebar goes.
            if controller.previewMode == .split, width < PreviewLayout.minimumSplitWidth { makeRoomForSplit() }
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

    /// One editor for all files. Each file has its own `documentId` and text binding, so the engine
    /// keeps undo and scroll position per file, and an edit lands in the file it was made in.
    /// `width` is the editor's part of the detail area.
    private func editor(_ file: MarcdownFile, width: CGFloat) -> some View {
        NativeTextViewWrapper(
            text: Binding(get: { file.text }, set: { file.edit($0) }),
            configuration: configuration(width: width, folder: file.url?.deletingLastPathComponent()),
            fontName: appearance.fontName,
            fontSize: appearance.fontSize,
            documentId: file.id.uuidString,
            retainedScrollDocumentIds: Set(files.files.map(\.id.uuidString)),   // closed files drop their undo
            // The text view's mouse tracking fires under the overlay too: no I-beam over the preview.
            isCursorExcluded: { _ in controller.editorIsHidden },
            onTextViewReady: { controller.attach($0) },
            onWillPaste: { controller.dropPaste.willPaste(in: $0, pasteboard: $1) },
            onDropFiles: { controller.dropPaste.drop(in: $0, info: $1, insertionIndex: $2) },
            onSaveRequest: { _ in controller.saveRequested() },
            onDocumentShown: { _ in controller.fileShown(file) }
        )
    }

    /// Side by side needs room for both halves: hide the sidebar, then widen the window if that is not enough.
    private func makeRoomForSplit() {
        let needed = PreviewLayout.minimumSplitWidth
        guard detailWidth < needed else { return }
        columnVisibility = .detailOnly
        guard let window = files.window, window.contentLayoutRect.width < needed else { return }
        var frame = window.frame
        frame.size.width += needed - window.contentLayoutRect.width
        if let screen = window.screen?.visibleFrame {
            frame.size.width = min(frame.width, screen.width)
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
        }
        window.setFrame(frame, display: true, animate: true)
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

    private var title: String { files.selected?.title ?? "Marcdown" }

    /// Point the editor controller at the selected file. The engine shows it a turn later (`fileShown`).
    private func sync() {
        controller.file = files.selected
        controller.lint.clear()
    }

    /// `width` is the editor width; `folder` resolves relative images; with a width limit the horizontal inset centers the text.
    private func configuration(width: CGFloat, folder: URL?) -> MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration()
        config.services.images = FileImageProvider(baseURL: folder)
        config.extensions = [StrikethroughExtension()]
        let style = DocumentStyle(settings: appearance)
        style.apply(to: &config)   // the same measures and colors as the Preview
        config.rawSourceMode = appearance.showsMarkdownSource
        config.lists.autoClosePairsEnabled = false
        config.spellChecking.automaticQuoteSubstitution = false
        config.textInsets = TextInsets(
            horizontal: AppearanceSettings.horizontalInset(forWidth: width, columnWidth: style.columnWidth, minimum: 24),
            vertical: 16
        )
        // A fixed ~2-line slack below the last line; the engine default (25% of the viewport) leaves half a window empty.
        config.overscroll = OverscrollPolicy(percent: 0, maxPoints: 48, minPoints: 48)
        return config
    }
}
