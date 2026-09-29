import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggle = Self("toggle", default: .init(.space, modifiers: [.option]))
}

struct SettingsView: View {
    @AppStorage(SkinTone.key) private var skinTone = 0

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .toggle)
            Picker("Skin tone:", selection: $skinTone) {
                ForEach(SkinTone.names.indices, id: \.self) { tone in
                    Text("\(SkinTone.sample(tone)) \(SkinTone.names[tone])").tag(tone)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let picker = PickerController()
    private let loginItem = NSMenuItem(title: "Launch at Login",
                                       action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
    private var statusItem: NSStatusItem!
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        // Accessibility is required to post ⌘V into other apps. Prompts once.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        KeyboardShortcuts.onKeyDown(for: .toggle) { [picker] in picker.toggle() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "😀"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show Picker", action: #selector(showPicker), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func showPicker() { picker.show() }

    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
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
