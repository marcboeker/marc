import Foundation

/// What a sidebar row selects. A pinned row selects its pin, also when the file is open.
enum SidebarItem: Hashable {
    case file(MarcdownFile.ID)
    case pin(Pin.ID)
}

/// One sidebar row: an open file (with its pin when it is pinned), or a pin whose file is closed.
enum SidebarRow: Identifiable {
    case file(MarcdownFile, pin: Pin?)
    case closedPin(Pin)

    var id: SidebarItem { selection }

    var file: MarcdownFile? {
        switch self {
        case .file(let file, _): file
        case .closedPin: nil
        }
    }

    var pin: Pin? {
        switch self {
        case .file(_, let pin): pin
        case .closedPin(let pin): pin
        }
    }

    var selection: SidebarItem {
        switch self {
        case .file(let file, nil): .file(file.id)
        case .file(_, let pin?), .closedPin(let pin): .pin(pin.id)
        }
    }

    /// Nil for an untitled file.
    var url: URL? {
        switch self {
        case .file(let file, _): file.url
        case .closedPin(let pin): pin.url
        }
    }

    var displayName: String {
        switch self {
        case .file(let file, _): file.displayName
        case .closedPin(let pin): pin.name
        }
    }
}

/// The sidebar's file sections. A pinned file shows only in `pinned`, open or not.
struct SidebarRows {
    /// One row per pin, in pin order.
    let pinned: [SidebarRow]
    /// The open files that are not pinned, in open order.
    let open: [SidebarRow]

    var all: [SidebarRow] { pinned + open }
}
