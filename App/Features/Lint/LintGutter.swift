import AppKit

/// Small icon buttons placed at the right edge of lines with issues. They are subviews of the
/// text view, so they scroll with the text. Positions come from TextKit 2 line fragments.
@MainActor
final class LintGutter {
    private weak var textView: NSTextView?
    private var issues: [LintIssue] = []
    private var buttons: [IssueButton] = []
    private var observers: [NSObjectProtocol] = []
    private var popover: NSPopover?
    private var layoutScheduled = false

    private static let size: CGFloat = 12

    func attach(to textView: NSTextView) {
        observers.forEach(NotificationCenter.default.removeObserver)
        self.textView = textView
        textView.postsFrameChangedNotifications = true
        let names: [Notification.Name] = [
            NSView.frameDidChangeNotification, NSText.didChangeNotification,
            NSTextView.didChangeSelectionNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleLayout() }
            }
        }
        rebuild()
    }

    func show(_ issues: [LintIssue]) {
        guard issues != self.issues else { return }
        self.issues = issues
        rebuild()
    }

    private func rebuild() {
        popover?.close()
        buttons.forEach { $0.removeFromSuperview() }
        guard let textView else { return }
        buttons = issues.map { issue in
            let button = IssueButton(issue: issue)
            button.target = self
            button.action = #selector(toggleMessage(_:))
            textView.addSubview(button)
            return button
        }
        layoutIcons()
    }

    /// Coalesce bursts (typing, selection changes restyle lines after the notification fires).
    private func scheduleLayout() {
        guard !layoutScheduled else { return }
        layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.layoutScheduled = false
            self?.layoutIcons()
        }
    }

    private func layoutIcons() {
        guard !buttons.isEmpty, let textView, let tlm = textView.textLayoutManager, let content = tlm.textContentManager else { return }
        let starts = Self.lineStarts(of: textView.string)
        let origin = textView.textContainerOrigin
        let x = textView.bounds.width - Self.size - 4
        for button in buttons {
            let line = button.issue.line
            var frame: CGRect?
            if line >= 1, line <= starts.count, let location = content.location(tlm.documentRange.location, offsetBy: starts[line - 1]) {
                let range = NSTextRange(location: location)
                tlm.ensureLayout(for: range)
                tlm.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
                    frame = segment
                    return false
                }
            }
            guard let frame else { button.isHidden = true; continue }
            button.isHidden = false
            button.frame = CGRect(x: x, y: origin.y + frame.midY - Self.size / 2, width: Self.size, height: Self.size)
        }
    }

    /// UTF-16 offset of the first character of each line.
    private static func lineStarts(of text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }

    @objc private func toggleMessage(_ sender: IssueButton) {
        if let popover, popover.isShown { popover.close(); if popover.contentViewController?.representedObject as? IssueButton === sender { return } }
        let label = NSTextField(wrappingLabelWithString: sender.issue.message)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 260
        let holder = NSViewController()
        holder.representedObject = sender
        holder.view = NSView()
        holder.view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.view.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: holder.view.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: holder.view.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: holder.view.bottomAnchor, constant: -6),
        ])
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = holder
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        self.popover = popover
    }
}

/// Never becomes first responder, so typing focus stays in the text view.
private final class IssueButton: NSButton {
    let issue: LintIssue

    init(issue: LintIssue) {
        self.issue = issue
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Lint issue")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        contentTintColor = .tertiaryLabelColor
        alphaValue = 0.7
        focusRingType = .none
        toolTip = issue.message
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
}
