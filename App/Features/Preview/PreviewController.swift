import AppKit
import CryptoKit
import WebKit

/// The window's rendered preview: one web view for the window's life, so a mode switch or a file
/// switch does not reload it. It loads the page once; later text, folder and style changes go
/// through our script (`marcPreview.update`). JavaScript of the page itself is off. The page and its
/// files come through `PreviewScheme`: the web view reads no files itself, and frames do not load.
@MainActor
@Observable
final class PreviewController: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// Find bar of the overlay (Edit > Find while the preview replaces the editor).
    var isFinding = false
    var findText = ""
    /// The last search found nothing.
    var findFailed = false

    @ObservationIgnored private weak var editor: EditorController?
    @ObservationIgnored private(set) lazy var webView = makeWebView()
    @ObservationIgnored private let scheme = PreviewSchemeHandler()
    /// The rule list that blocks frames is in, so a page can load.
    @ObservationIgnored private var rulesReady = false
    @ObservationIgnored private var loadState = LoadState.idle
    /// Scripts that wait for the page to finish loading.
    @ObservationIgnored private var pending: [(body: String, arguments: [String: Any], then: Completion?)] = []

    /// What the page shows now.
    @ObservationIgnored private var shown: (text: String, folder: URL?, style: DocumentStyle?) = ("", nil, nil)
    @ObservationIgnored private var sourceMap = PreviewSourceMap(html: "")
    /// The blocks the page has after the scripts sent so far, and whether it knows how they split.
    @ObservationIgnored private var sentBody = PreviewBody.empty
    @ObservationIgnored private var pageKnowsBlocks = false
    @ObservationIgnored private var style: DocumentStyle?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var lastScroll: PreviewSourceMap.Target?
    @ObservationIgnored private var scrollObserver: NSObjectProtocol?
    @ObservationIgnored private var scrollSyncQueued = false

    /// Time after the last edit before the preview renders again.
    static let debounce: Duration = .milliseconds(150)

    private typealias Completion = @MainActor (Result<Any, any Error>) -> Void

    private enum LoadState: Equatable {
        case idle
        /// The page loads once the rule list is in.
        case waitingForRules(page: String)
        case loading
        case loaded
    }

    init(editor: EditorController) {
        self.editor = editor
        super.init()
        // Files only from the folder the page shows now.
        scheme.folder = { [weak self] in self?.shown.folder }
    }

    isolated deinit {
        stopScrollSync()
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The page is the user's own Markdown, but raw HTML in it must not run scripts.
        // Our script runs in its own content world, which this does not turn off.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(scheme, forURLScheme: PreviewScheme.name)
        configuration.userContentController.addUserScript(WKUserScript(
            source: PreviewRenderer.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // The window background shows through, the same as behind the editor. `drawsBackground` is
        // not public API: without it the page has the opaque default background, but no crash.
        if webView.responds(to: NSSelectorFromString("_setDrawsBackground:"))
            || webView.responds(to: NSSelectorFromString("setDrawsBackground:")) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        webView.underPageBackgroundColor = .clear
        // A drop would load the dropped file in place of the preview.
        webView.unregisterDraggedTypes()
        addRules(to: configuration.userContentController)
        return webView
    }

    /// Frames (`<iframe>`, `<frame>`, `<object>` in raw HTML) never load. `decidePolicyFor` cancels
    /// them too; the rule list also stops what the navigation delegate is not asked about.
    private static let rules = #"[{"trigger":{"url-filter":".*","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"block"}}]"#
    /// WebKit keeps compiled lists between launches. The name has a hash of the rules, so a
    /// stored list with older rules is never used.
    private static let rulesIdentifier = "MarcPreviewNoFrames-"
        + SHA256.hash(data: Data(rules.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    /// The list once one window has it; later windows add it at once.
    private static var noFrames: WKContentRuleList?

    /// Add the rule list: the stored one, else compile it. No page loads before it is in.
    private func addRules(to contentController: WKUserContentController) {
        if let list = Self.noFrames {
            contentController.add(list)
            rulesReady = true
            // The web view is not set yet: a waiting page loads next turn.
            DispatchQueue.main.async { [weak self] in self?.loadWaitingPage() }
            return
        }
        let store = WKContentRuleListStore.default()
        store?.lookUpContentRuleList(forIdentifier: Self.rulesIdentifier) { [weak self] list, _ in
            MainActor.assumeIsolated {
                if let list { return self?.rulesAdded(list, to: contentController) ?? () }
                store?.compileContentRuleList(forIdentifier: Self.rulesIdentifier, encodedContentRuleList: Self.rules) { [weak self] list, _ in
                    MainActor.assumeIsolated { self?.rulesAdded(list, to: contentController) }
                }
            }
        }
    }

    private func rulesAdded(_ list: WKContentRuleList?, to contentController: WKUserContentController) {
        if let list {
            Self.noFrames = list
            contentController.add(list)
        }
        rulesReady = true
        loadWaitingPage()
    }

    private func loadWaitingPage() {
        if case .waitingForRules(let page) = loadState { load(page) }
    }

    // MARK: Rendering

    /// Called by the preview view on every SwiftUI update with the file's text and folder: an edit
    /// renders after `debounce`, a new file, folder or style renders now. The render itself takes the
    /// editor's text, which `text` trails by one run-loop turn.
    func refresh(text: String, folder: URL?, style: DocumentStyle) {
        self.style = style
        if folder != shown.folder || style != shown.style || loadState == .idle {
            render()
        } else if text != shown.text {
            scheduleRender()
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    /// Render the editor's freshest text now.
    func render() {
        renderTask?.cancel()
        guard let editor else { return }
        let style = style ?? DocumentStyle(settings: .shared)
        let text = editor.currentText
        let folder = editor.documentFolder
        let rendering = PreviewRenderer.render(markdown: text)
        shown = (text, folder, style)
        sourceMap = rendering.sourceMap
        lastScroll = nil
        if loadState == .idle {
            sentBody = rendering.body
            pageKnowsBlocks = false
            load(PreviewRenderer.page(body: rendering.html, baseFolder: folder, style: style))
        } else {
            let change = rendering.body.change(from: sentBody, pageKnowsBlocks: pageKnowsBlocks)
            sentBody = rendering.body
            pageKnowsBlocks = true
            update(change, base: PreviewScheme.base(folder), css: PreviewRenderer.stylesheet(style))
        }
        if editor.previewMode == .split { syncToEditor() }
    }

    /// The page did not have the blocks Swift has (or the script failed): send all of them.
    private func update(_ change: PreviewBody.Change, base: String, css: String) {
        run("return marcPreview.update(base, css, change)", ["base": base, "css": css, "change": change.arguments]) { [weak self] result in
            guard let self, !change.full else { return }
            if case .success(let value) = result, (value as? NSNumber)?.intValue != -1 { return }
            update(sentBody.full, base: base, css: css)
        }
    }

    private func load(_ html: String) {
        guard rulesReady else {
            loadState = .waitingForRules(page: html)
            return
        }
        loadState = .loading
        scheme.page = html
        webView.load(URLRequest(url: PreviewScheme.pageURL))
    }

    /// Our script, in our content world. Before the page is in, it waits.
    private func run(_ body: String, _ arguments: [String: Any] = [:], then: Completion? = nil) {
        guard loadState == .loaded else {
            pending.append((body, arguments, then))
            return
        }
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .defaultClient, completionHandler: then)
    }

    // MARK: Modes and scrolling

    /// The window switched modes. Renders now if the page is stale, so the preview never shows an old text.
    func modeChanged(to mode: PreviewMode) {
        stopScrollSync()
        if mode != .overlay { closeFind(focusing: false) }
        guard let editor else { return }
        // The page may have scrolled on its own since: the next sync scrolls, even to the same place.
        lastScroll = nil
        if mode != .editor && isStale { render() }
        // Next turn: SwiftUI has put the web view in the window at its new size.
        DispatchQueue.main.async { [weak self, weak editor] in
            guard let self, let editor, editor.previewMode == mode else { return }
            settle(mode)
            if mode == .overlay { focus() } else { editor.focusTextView() }
        }
    }

    /// The page is not loaded, or shows another text, folder or style than the editor has now.
    private var isStale: Bool {
        guard let editor else { return false }
        return loadState == .idle || shown.text != editor.currentText || shown.folder != editor.documentFolder
            || style != nil && style != shown.style
    }

    /// The engine shows another file (its text, selection and scroll position are in).
    func fileShown() {
        guard let mode = editor?.previewMode, mode != .editor else { return }
        render()
        settle(mode)
        if mode == .overlay { focus() }
    }

    /// Put the page where `mode` wants it after a render: at the cursor under the overlay;
    /// side by side, follow the editor's scroll view (the engine may have a new one).
    private func settle(_ mode: PreviewMode) {
        switch mode {
        case .overlay:
            scrollToCursor()
        case .split:
            startScrollSync()
            syncToEditor()
        case .editor:
            break
        }
    }

    /// Make the web view take the keys: letters do nothing, menu shortcuts still work.
    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    /// Scroll to the element with the cursor line.
    func scrollToCursor() {
        guard let editor else { return }
        scroll(toEditorLine: sourceMap.line(atUTF16Offset: editor.selectedRange.location), force: true)
    }

    private func scroll(toEditorLine line: Int, force: Bool = false) {
        guard let target = sourceMap.target(forEditorLine: line), force || target != lastScroll else { return }
        lastScroll = target
        run("marcPreview.scrollToBlock(position, fraction)", ["position": target.position, "fraction": target.fraction])
    }

    /// Split: follow the editor's top visible line. One way only. Lines count in the rendered text:
    /// the source map is for it. Until the next render (at most `debounce` after an edit) the
    /// offset can be some characters off; the render syncs again.
    private func syncToEditor() {
        guard let textView = editor?.textView else { return }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let point = NSPoint(x: origin.x + 4, y: max(visible.minY, origin.y) + 1)
        let index = textView.characterIndexForInsertion(at: point)
        scroll(toEditorLine: sourceMap.line(atUTF16Offset: index))
    }

    private func startScrollSync() {
        stopScrollSync()
        guard let clip = editor?.textView?.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.queueScrollSync() }
        }
    }

    private func stopScrollSync() {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
    }

    /// One sync per run-loop turn, however many scroll events come in.
    private func queueScrollSync() {
        guard !scrollSyncQueued else { return }
        scrollSyncQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scrollSyncQueued = false
            if editor?.previewMode == .split { syncToEditor() }
        }
    }

    // MARK: Find

    /// Edit > Find while the preview replaces the editor: find in the rendered text.
    func performFind(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface, .showReplaceInterface:
            isFinding = true
        case .nextMatch:
            find(backwards: false)
        case .previousMatch:
            find(backwards: true)
        case .setSearchString:
            webView.callAsyncJavaScript("return marcPreview.selectedText()", arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
                guard let self, case .success(let value) = result, let text = value as? String, !text.isEmpty else { return }
                findText = text
                isFinding = true
            }
        case .hideFindInterface:
            closeFind()
        default:
            break
        }
    }

    /// From the find bar while typing: start again at the top, so the first match shows.
    func findFromTop() {
        webView.callAsyncJavaScript("marcPreview.clearSelection()", arguments: [:], in: nil, in: .defaultClient) { [weak self] _ in
            self?.find(backwards: false)
        }
    }

    func find(backwards: Bool) {
        guard !findText.isEmpty else {
            findFailed = false
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(findText, configuration: configuration) { [weak self] result in
            guard let self else { return }
            findFailed = !result.matchFound
            // WebKit scrolls the match just into view, at the edge; put it in the middle.
            if result.matchFound { run("marcPreview.centerSelection()") }
        }
    }

    /// Done or Esc in the find bar: the match highlight (the selection) goes too.
    func closeFind(focusing: Bool = true) {
        guard isFinding else { return }
        isFinding = false
        findFailed = false
        // WebKit has no call to hide its match highlight; a search that finds nothing removes it.
        webView.find(UUID().uuidString, configuration: WKFindConfiguration()) { _ in }
        run("marcPreview.clearSelection()")
        if focusing { focus() }
    }

    // MARK: Navigation

    /// Only our own page loads. A link click is opened by Marc or the default app, never in here.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            follow(url)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame {
            // A Reload from the context menu: the page has only the first render, so render again ourselves.
            if navigationAction.navigationType == .reload {
                decisionHandler(.cancel)
                reload()
                return
            }
            decisionHandler(loadState == .loading && url == PreviewScheme.pageURL ? .allow : .cancel)
        } else {
            decisionHandler(.cancel)   // an <iframe> in raw HTML: frames never load
        }
    }

    /// Links with `target="_blank"`: the same as a click, no new web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { follow(url) }
        return nil
    }

    private func follow(_ url: URL) {
        switch PreviewLink.classify(url, baseFolder: shown.folder) {
        case .anchor(let name):
            run("marcPreview.scrollToAnchor(name)", ["name": name])
        case .markdownFile(let file):
            OpenFiles.shared.open(file)
        case .localFile(let file):
            NSWorkspace.shared.activateFileViewerSelecting([file])
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .ignored:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadState = .loaded
        let scripts = pending
        pending = []
        for script in scripts { run(script.body, script.arguments, then: script.then) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed()
    }

    /// The web content process quit or crashed: the page is gone.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }

    private func loadFailed() {
        if loadState == .loading { loadState = .idle }
        pending = []
    }

    private func reload() {
        loadState = .idle
        pending = []
        render()
        if let mode = editor?.previewMode { settle(mode) }
    }
}
