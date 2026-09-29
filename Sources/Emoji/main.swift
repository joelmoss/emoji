import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggle = Self("toggle", default: .init(.space, modifiers: [.option]))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let picker = PickerController()
    private var statusItem: NSStatusItem!
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        // Accessibility is required to post ⌘V into other apps. Prompts once.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        KeyboardShortcuts.onKeyDown(for: .toggle) { [picker] in picker.toggle() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "😀"
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Picker", action: #selector(showPicker), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showPicker() { picker.show() }

    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView:
                Form { KeyboardShortcuts.Recorder("Shortcut:", name: .toggle) }.padding(20)))
            window.title = "Emoji Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settings = window
        }
        NSApp.activate()
        settings?.center()
        settings?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
