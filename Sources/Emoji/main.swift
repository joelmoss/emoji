import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// The dev build (`make dev`) has its own bundle id, so it keeps its own settings, recents and
/// Accessibility grant, and can run beside the release app.
enum Variant {
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
}

extension KeyboardShortcuts.Name {
    // Different default so dev and release don't fight over ⌥Space.
    static let toggle = Self("toggle", default: .init(.space, modifiers: Variant.isDev ? [.option, .shift] : [.option]))
}

/// The recorder needs a real window: a menu's tracking loop swallows the keystrokes it records.
struct ShortcutRecorderView: View {
    var body: some View {
        Form { KeyboardShortcuts.Recorder("Shortcut:", name: .toggle) }
            .padding(20)
            .frame(width: 320)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Menu presets. ⌘Space, ⌃Space and ⌘⌥Space are taken by macOS itself.
    private static let shortcutPresets: [KeyboardShortcuts.Shortcut] = [
        [.option], [.option, .shift], [.control, .option], [.command, .shift], [.control, .shift]
    ].map { .init(.space, modifiers: $0) }

    private let picker = PickerController()
    private let showPickerItem = NSMenuItem(title: "Show Picker", action: #selector(showPicker), keyEquivalent: "")
    private static let hideIconKey = "hideMenuBarIcon"
    private static let iconKey = "menuBarIcon"
    /// Menu-bar icon choices; a nil symbol means the 😀 emoji. Symbols are template images.
    private static let icons: [(name: String, symbol: String?)] = [
        ("Emoji", nil), ("Smiley", "face.smiling"), ("Solid Smiley", "smiley.fill"),
        ("Dashed Face", "face.dashed"), ("Keyboard", "keyboard"), ("Speech Bubble", "character.bubble")
    ]

    private let statusIconItem = NSMenuItem(title: "Show Menu Bar Icon",
                                            action: #selector(toggleStatusIcon),
                                            keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login",
                                       action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
    private let customShortcutItem = NSMenuItem(title: "Custom…",
                                                action: #selector(showShortcutRecorder),
                                                keyEquivalent: "")
    private let skinMenu = NSMenu()
    private let iconMenu = NSMenu()
    private let shortcutMenu = NSMenu()
    private var statusItem: NSStatusItem!
    private var recorderWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        // Accessibility is required to post ⌘V into other apps. Prompts once.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        KeyboardShortcuts.onKeyDown(for: .toggle) { [picker] in picker.toggle() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        applyIcon()
        statusItem.menu = makeMenu()
        statusItem.isVisible = !UserDefaults.standard.bool(forKey: Self.hideIconKey)
        picker.menu = statusItem.menu
    }

    /// Relaunching the app (Finder, Spotlight) opens the picker: the way back in when the icon is
    /// hidden and the shortcut is cleared.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        picker.show()
        return false
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        showPickerItem.target = self
        menu.addItem(showPickerItem)

        for (tone, name) in SkinTone.names.enumerated() {
            let item = NSMenuItem(title: "\(SkinTone.sample(tone)) \(name)",
                                  action: #selector(selectSkinTone), keyEquivalent: "")
            item.tag = tone
            item.target = self
            skinMenu.addItem(item)
        }
        menu.addItem(withTitle: "Skin Tone", action: nil, keyEquivalent: "").submenu = skinMenu

        for (index, icon) in Self.icons.enumerated() {
            let item = NSMenuItem(title: icon.name, action: #selector(selectIcon), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.image = icon.symbol.flatMap(Self.symbolImage)
            iconMenu.addItem(item)
        }
        menu.addItem(withTitle: "Icon", action: nil, keyEquivalent: "").submenu = iconMenu

        for preset in Self.shortcutPresets {
            let item = NSMenuItem(title: "\(preset)", action: #selector(selectShortcut), keyEquivalent: "")
            item.representedObject = preset
            item.target = self
            shortcutMenu.addItem(item)
        }
        shortcutMenu.addItem(.separator())
        customShortcutItem.target = self
        shortcutMenu.addItem(customShortcutItem)
        shortcutMenu.addItem(withTitle: "Clear", action: #selector(clearShortcut), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Shortcut", action: nil, keyEquivalent: "").submenu = shortcutMenu

        statusIconItem.target = self
        menu.addItem(statusIconItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    func menuNeedsUpdate(_: NSMenu) {
        showPickerItem.isHidden = picker.isVisible  // this menu is also the picker's gear menu
        statusIconItem.state = statusItem.isVisible ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for item in skinMenu.items { item.state = item.tag == SkinTone.current ? .on : .off }
        for item in iconMenu.items { item.state = item.tag == selectedIcon ? .on : .off }

        let current = KeyboardShortcuts.getShortcut(for: .toggle)
        for item in shortcutMenu.items {
            if let preset = item.representedObject as? KeyboardShortcuts.Shortcut {
                item.state = preset == current ? .on : .off
            }
        }
        // A recorded shortcut that isn't a preset shows as "Custom…" with its keys.
        let custom = current.flatMap { Self.shortcutPresets.contains($0) ? nil : $0 }
        customShortcutItem.title = custom.map { "Custom (\($0))…" } ?? "Custom…"
        customShortcutItem.state = custom == nil ? .off : .on
    }

    private var selectedIcon: Int {
        let index = UserDefaults.standard.integer(forKey: Self.iconKey)
        return Self.icons.indices.contains(index) ? index : 0
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Emoji picker")
        image?.isTemplate = true
        return image
    }

    /// The dev build adds 🛠️ next to whichever icon is chosen, to tell it apart from release.
    private func applyIcon() {
        guard let button = statusItem.button else { return }
        let symbol = Self.icons[selectedIcon].symbol
        button.image = symbol.flatMap(Self.symbolImage)
        button.imagePosition = .imageLeading
        button.title = (button.image == nil ? "😀" : "") + (Variant.isDev ? "🛠️" : "")
    }

    @objc private func selectIcon(_ item: NSMenuItem) {
        UserDefaults.standard.set(item.tag, forKey: Self.iconKey)
        applyIcon()
    }

    @objc private func selectSkinTone(_ item: NSMenuItem) {
        UserDefaults.standard.set(item.tag, forKey: SkinTone.key)
    }

    @objc private func selectShortcut(_ item: NSMenuItem) {
        KeyboardShortcuts.setShortcut(item.representedObject as? KeyboardShortcuts.Shortcut, for: .toggle)
    }

    @objc private func clearShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .toggle)
    }

    @objc private func toggleStatusIcon() {
        statusItem.isVisible.toggle()
        UserDefaults.standard.set(!statusItem.isVisible, forKey: Self.hideIconKey)
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

    @objc private func showShortcutRecorder() {
        if recorderWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutRecorderView()))
            window.title = "Emoji Shortcut"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            recorderWindow = window
        }
        // Not plain activate(): on macOS 14+ it's cooperative and is declined while another app is
        // frontmost, so the window never becomes key and the recorder never sees keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        recorderWindow?.center()
        recorderWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
