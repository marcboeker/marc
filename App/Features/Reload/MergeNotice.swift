import SwiftUI

/// One merge result to show. Each merge gets a new id, so a second merge restarts the timer.
struct MergeNotice: Equatable, Identifiable {
    let id = UUID()
    let conflicts: Int

    var message: String {
        switch conflicts {
        case 0: "Merged"
        case 1: "Merged · 1 conflict"
        default: "Merged · \(conflicts) conflicts"
        }
    }
}

/// A small capsule at the bottom of the editor. It fades out by itself; a click selects the first conflict.
struct MergeNoticeView: View {
    let notice: MergeNotice
    let onClick: () -> Void
    let onTimeout: () -> Void

    var body: some View {
        Text(notice.message)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .contentShape(Capsule())
            .onTapGesture(perform: onClick)
            .help(notice.conflicts > 0 ? "Select the first conflict" : "")
            .task(id: notice.id) {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { onTimeout() }
            }
    }
}
