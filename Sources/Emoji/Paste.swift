import AppKit

enum Paste {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// nspasteboard.org convention: clipboard managers skip anything carrying this type, so a picked emoji
    /// doesn't become a history entry.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Puts `text` on the pasteboard, sends ⌘V to the frontmost app, then restores the old clipboard.
    /// Posting the key event needs Accessibility; without it the emoji is left on the clipboard instead.
    static func insert(_ text: String) {
        guard AXIsProcessTrusted() else {
            write(text, to: .general, transient: false)
            explainAccessibility()
            return
        }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let stamp = write(text, to: pasteboard, transient: true)

        // Let the picker panel finish closing so the target app is key again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                // ponytail: keycode 9 = physical V key; wrong on layouts that remap ⌘V (e.g. Dvorak-QWERTY ⌘)
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cgAnnotatedSessionEventTap)
            }
            // ponytail: fixed 0.3s wait; an app slower than that still pastes the restored clipboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                restore(saved, to: pasteboard, unlessChangedSince: stamp)
            }
        }
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    /// Replaces the clipboard with `text`; returns the pasteboard's change count right after, to spot later changes.
    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard, transient: Bool) -> Int {
        pasteboard.clearContents()
        pasteboard.declareTypes(transient ? [.string, transientType] : [.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        if transient { pasteboard.setData(Data(), forType: transientType) }
        return pasteboard.changeCount
    }

    /// Puts `saved` back, unless something else wrote to the clipboard since `stamp`: a copy made in that
    /// window belongs to the user and must not be overwritten.
    static func restore(_ saved: Snapshot, to pasteboard: NSPasteboard, unlessChangedSince stamp: Int) {
        guard pasteboard.changeCount == stamp else { return }
        pasteboard.clearContents()
        for item in saved {
            let restored = NSPasteboardItem()
            for (type, data) in item { restored.setData(data, forType: type) }
            pasteboard.writeObjects([restored])
        }
    }

    private static func explainAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Emoji copied, but not pasted"
        alert.informativeText = "Emoji needs Accessibility access to paste for you. "
            + "The emoji is on your clipboard now: press ⌘V to paste it."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
