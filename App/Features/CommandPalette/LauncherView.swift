import AppKit
import SwiftUI

/// View > Command Launcher… (⇧⌘P). Page Setup moved to ⌥⇧⌘P for it.
struct LauncherCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(CommandLauncher.menuTitle) { CommandLauncher.shared.open() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
        }
    }
}

/// Over the main window's content (ContentView): the launcher at the top center, like VS Code. A click
/// beside it closes it and goes no further.
struct LauncherOverlay: View {
    private var launcher = CommandLauncher.shared

    var body: some View {
        if launcher.isOpen {
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { launcher.close() }
                LauncherPanel(launcher: launcher)
                    .padding(.top, 8)
            }
        }
    }
}

/// The search field and the rows: dimmed prefix and title left, shortcut right, about ten in sight, then the list scrolls.
private struct LauncherPanel: View {
    let launcher: CommandLauncher
    @FocusState private var focused: Bool
    /// Where the pointer was at the last selection by hover, typing or open. Rows that scroll under a pointer
    /// that did not move get a hover too; those must not take the selection from the keys.
    @State private var pointer = NSEvent.mouseLocation

    private static let rowHeight: CGFloat = 26
    private static let visibleRows = 10
    private static let top = "launcher.top", bottom = "launcher.bottom"
    private let shape = RoundedRectangle(cornerRadius: 12)

    var body: some View {
        @Bindable var launcher = launcher
        VStack(spacing: 0) {
            TextField("Search commands and files", text: $launcher.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .focused($focused)
                .onKeyPress(.upArrow) { launcher.move(by: -1); return .handled }
                .onKeyPress(.downArrow) { launcher.move(by: 1); return .handled }
                .onSubmit { launcher.runSelection() }
                .onExitCommand { launcher.close() }
            Divider()
            list
        }
        .frame(width: 560)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        // A turn after the field appears: before that it is not in the window yet and the editor keeps the focus.
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: launcher.focusRequest) { focused = true }
        .onChange(of: launcher.query) { pointer = NSEvent.mouseLocation }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 6).id(Self.top)
                    ForEach(Array(launcher.rows.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == launcher.selection)
                            .onHover { inside in
                                guard inside, NSEvent.mouseLocation != pointer else { return }
                                pointer = NSEvent.mouseLocation
                                launcher.select(index)
                            }
                            .onTapGesture { launcher.run(item) }
                    }
                    if launcher.rows.isEmpty {
                        Text("No Matches")
                            .foregroundStyle(.secondary)
                            .frame(height: Self.rowHeight)
                    }
                    Color.clear.frame(height: 6).id(Self.bottom)
                }
                .padding(.horizontal, 6)
            }
            .frame(height: CGFloat(min(max(launcher.rows.count, 1), Self.visibleRows)) * Self.rowHeight + 12)
            .onChange(of: launcher.selection) { _, index in
                // The ends scroll to the margins, so a wrap shows the first or last row with its space.
                let rows = launcher.rows
                guard rows.indices.contains(index) else { return }
                proxy.scrollTo(index == 0 ? Self.top : index == rows.count - 1 ? Self.bottom : rows[index].id)
            }
        }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        let dimmed = selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary)
        return HStack(spacing: 0) {
            if !item.category.isEmpty {
                Text(item.category + ": ")
                    .foregroundStyle(dimmed)
            }
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 16)
            Text(item.shortcut)
                .foregroundStyle(dimmed)
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .id(item.id)
    }
}
