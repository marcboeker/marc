//  Marcdown: lets the embedder run code before an explicit save (⌘S / File > Save).
//  Autosave never sends `save:`, so it does not pass through here.

import AppKit

extension NativeTextView {
    @objc(saveDocument:) func saveDocument(_ sender: Any?) {
        if onSaveRequest?(self) == true { return }
        nextResponder?.tryToPerform(#selector(NSDocument.save(_:)), with: sender)
    }
}
