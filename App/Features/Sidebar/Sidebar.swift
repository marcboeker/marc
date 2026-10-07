import SwiftUI
import UniformTypeIdentifiers

/// The main window's sidebar: the pinned files on top, then the other open files, the shown file's
/// outline below. Click a file to show it; a click on a closed pin opens it. Drop Markdown or text
/// files here to open them (a drop on the editor inserts links instead, see DropPaste).
struct Sidebar: View {
    let controller: EditorController
    private let files = OpenFiles.shared

    /// A drop opens Markdown and plain text (not source code or JSON, which also conform to plain text).
    private static func opens(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return url.isMarkdownFile || UTType(filenameExtension: url.pathExtension) == .plainText
    }

    var body: some View {
        let rows = files.sidebarRows
        // One pass over both sections, so a folder shows only when two names clash.
        let all = rows.all
        let labels = Dictionary(uniqueKeysWithValues: zip(
            all.map(\.id),
            FileLabels.labels(for: all.map { (url: $0.url, displayName: $0.displayName) })
        ))
        List(selection: selection(rows)) {
            if !rows.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(rows.pinned) { row in
                        FileRow(row: row, label: labels[row.id]!)
                            .tag(row.selection)
                    }
                }
            }
            Section {
                ForEach(rows.open) { row in
                    FileRow(row: row, label: labels[row.id]!)
                        .tag(row.selection)
                }
            } header: {
                HStack {
                    Text("Open Files")
                    Spacer()
                    Text("\(rows.open.count)")
                        .monospacedDigit()
                        .padding(.trailing, 10)
                }
            }
            if let file = files.selected {
                OutlineSection(controller: controller, file: file)
            }
        }
        .listStyle(.sidebar)
        .dropDestination(for: URL.self) { urls, _ in
            let openable = urls.filter(Self.opens)
            openable.forEach(files.open)
            return !openable.isEmpty
        }
    }

    /// Through `OpenFiles.selectedID`, so the outgoing file keeps its text selection. A pinned file shows
    /// as selected in Pinned. A click on a pin goes through `OpenFiles.activate`, which opens a closed pin.
    /// A click on empty space (nil) keeps the shown file.
    private func selection(_ rows: SidebarRows) -> Binding<SidebarItem?> {
        Binding(
            get: { files.selectedID.flatMap { id in rows.all.first { $0.file?.id == id }?.selection } },
            set: { item in
                switch item {
                case .file(let id):
                    files.selectedID = id
                case .pin(let id):
                    if let pin = files.pins.items.first(where: { $0.id == id }) { files.activate(pin) }
                case nil:
                    break
                }
            }
        )
    }
}

/// One file: name, colliding folders, disk-change marker, and the unsaved dot, which the
/// close button replaces while the pointer is over the row. A closed pin has neither.
private struct FileRow: View {
    let row: SidebarRow
    let label: FileLabels.Label
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label.name)
                .lineLimit(1)
                .layoutPriority(1)
            if let folder = label.folder {
                Text(folder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            if let file = row.file, file.needsDiskReview {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(.orange)
                    .help("Changed on disk — select to review")
            }
            ZStack {
                if let file = row.file {
                    if hovering {
                        // Same path as ⌘W.
                        Button {
                            Task { await OpenFiles.shared.close(file) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close")
                    } else if file.isDirty {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 7, height: 7)
                            .help("Unsaved changes")
                    }
                }
            }
            .frame(width: 14)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(row.url?.path(percentEncoded: false) ?? row.displayName)   // untitled: only its name
        .contextMenu {
            if let pin = row.pin {
                Button("Unpin") { OpenFiles.shared.unpin(pin) }
            } else if let file = row.file {
                Button("Pin") { OpenFiles.shared.pins.pin(file.url) }
                    .disabled(file.url == nil)
            }
        }
    }
}
