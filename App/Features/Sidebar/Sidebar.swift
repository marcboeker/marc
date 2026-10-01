import SwiftUI
import UniformTypeIdentifiers

/// The main window's sidebar: the open files on top, the shown file's outline below.
/// Click a file to show it. Drop Markdown or text files here to open them (a drop on the editor
/// inserts links instead, see DropPaste).
struct Sidebar: View {
    let controller: EditorController
    private let files = OpenFiles.shared

    /// A drop opens Markdown and plain text (not source code or JSON, which also conform to plain text).
    private static func opens(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if url.pathExtension.lowercased() == "md" { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .markdown) || type == .plainText
    }

    var body: some View {
        let labels = FileLabels.labels(for: files.files.map { (url: $0.url, displayName: $0.displayName) })
        List(selection: selection) {
            Section {
                ForEach(Array(zip(files.files, labels)), id: \.0.id) { file, label in
                    FileRow(file: file, label: label)
                }
            } header: {
                HStack {
                    Text("Open Files")
                    Spacer()
                    Text("\(files.files.count)")
                        .monospacedDigit()
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

    /// Through `OpenFiles.selectedID`, so the outgoing file keeps its text selection. A click on
    /// empty space (nil) keeps the shown file.
    private var selection: Binding<MarcFile.ID?> {
        Binding(
            get: { files.selectedID },
            set: { id in
                if let id, files.files.contains(where: { $0.id == id }) { files.selectedID = id }
            }
        )
    }
}

/// One open file: name, colliding folders, disk-change marker, and the unsaved dot, which the
/// close button replaces while the pointer is over the row.
private struct FileRow: View {
    let file: MarcFile
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
            if file.needsDiskReview {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(.orange)
                    .help("Changed on disk — select to review")
            }
            ZStack {
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
            .frame(width: 14)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(tooltip)
    }

    /// The full path; an untitled file has only its name.
    private var tooltip: String {
        file.url?.path(percentEncoded: false) ?? file.displayName
    }
}
