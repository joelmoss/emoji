import AppKit

enum Paste {
    /// Puts `text` on the pasteboard, sends ⌘V to the frontmost app, then restores the old clipboard.
    /// Needs Accessibility permission to post the key event.
    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Let the picker panel finish closing so the target app is key again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                // ponytail: keycode 9 = physical V key; wrong on layouts that remap ⌘V (e.g. Dvorak-QWERTY ⌘)
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cgAnnotatedSessionEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                for item in saved {
                    let restored = NSPasteboardItem()
                    for (type, data) in item { restored.setData(data, forType: type) }
                    pasteboard.writeObjects([restored])
                }
            }
        }
    }
}
