import AppKit

enum Paste {
    /// Puts `text` on the pasteboard, sends ⌘V to the frontmost app, then restores the old clipboard.
    /// Needs Accessibility permission to post the key event.
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        }
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Let the picker panel finish closing so the target app is key again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                // ponytail: keycode 9 = physical V key; wrong on layouts that remap ⌘V (e.g. Dvorak-QWERTY ⌘)
                let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
                e?.flags = .maskCommand
                e?.post(tap: .cgAnnotatedSessionEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pb.clearContents()
                for item in saved {
                    let n = NSPasteboardItem()
                    for (t, d) in item { n.setData(d, forType: t) }
                    pb.writeObjects([n])
                }
            }
        }
    }
}
