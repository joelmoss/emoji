import AppKit
import SwiftUI

// MARK: - Panel

/// Chromeless, non-activating: the target app keeps focus, so paste lands in the right input.
final class PickerPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PickerView.width, height: PickerView.height),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentView = content
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // Borderless panels refuse key status by default; search field needs it to take typing.
    override var canBecomeKey: Bool { true }

    /// Set while the settings menu is open, so losing key status to the menu doesn't close the panel.
    var keepOpenOnResignKey = false

    // Click-away close. Non-activating means the app never becomes active,
    // so hidesOnDeactivate / applicationDidResignActive would never fire.
    override func resignKey() {
        super.resignKey()
        if !keepOpenOnResignKey { orderOut(nil) }
    }
}

// MARK: - Model

struct Pos: Hashable {
    var section = 0
    var index = 0
}

@Observable
final class PickerModel {
    static let cols = 9

    var query = ""
    var pos = Pos()
    var focusToken = 0
    var tone = 0
    private(set) var sections: [EmojiGroup] = []
    var onPick: (Emoji) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onSettings: () -> Void = {}

    /// Pass `sections` to pin the layout (tests); default builds it from recents + all groups.
    init(sections: [EmojiGroup]? = nil) {
        if let sections { self.sections = sections } else { refresh() }
    }

    var selected: Emoji? {
        guard sections.indices.contains(pos.section),
              sections[pos.section].emojis.indices.contains(pos.index) else { return nil }
        return sections[pos.section].emojis[pos.index]
    }

    func refresh() {
        pos = Pos()
        tone = SkinTone.current
        if query.isEmpty {
            let recent = Recents.list.compactMap { EmojiStore.byChar[$0] }
            sections = (recent.isEmpty ? [] : [EmojiGroup(name: "Recently Used", emojis: recent)]) + EmojiStore.groups
        } else {
            sections = [EmojiGroup(name: "Results", emojis: EmojiStore.search(query))]
        }
    }

    /// Left/right walk the flat list, spilling into the adjacent section.
    func moveHorizontally(by delta: Int) {
        guard count(pos.section) > 0 else { return }
        var section = pos.section
        var index = pos.index + delta
        if index < 0 {
            if section > 0 { section -= 1; index = count(section) - 1 } else { index = 0 }
        } else if index >= count(section) {
            if section < sections.count - 1 { section += 1; index = 0 } else { index = count(section) - 1 }
        }
        pos = Pos(section: section, index: index)
    }

    /// Up/down keep the column; partial last rows clamp.
    func moveVertically(by delta: Int) {
        guard count(pos.section) > 0 else { return }
        let cols = Self.cols
        let col = pos.index % cols
        var section = pos.section
        var index = pos.index + delta * cols
        if index < 0 {
            guard section > 0 else { return }
            section -= 1
            index = min((count(section) - 1) / cols * cols + col, count(section) - 1)
        } else if index >= count(section) {
            if pos.index / cols < (count(section) - 1) / cols {
                index = count(section) - 1
            } else if section < sections.count - 1 {
                section += 1
                index = min(col, count(section) - 1)
            } else {
                return
            }
        }
        pos = Pos(section: section, index: index)
    }

    private func count(_ section: Int) -> Int { sections[section].emojis.count }
}

// MARK: - View

/// Blurred backdrop with macOS 26's rounder corners. Glass is not stacked here: the search bar and
/// footer float on it as glass, and the grid scrolls underneath them.
private struct PanelBackground: ViewModifier {
    private static let radius: CGFloat = {
        if #available(macOS 26, *) { return 20 }
        return 12
    }()

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Self.radius))
            .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(.separator))
    }
}

/// Liquid Glass capsule on macOS 26+, a thin material capsule before that.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }
}

struct PickerView: View {
    static let cell: CGFloat = 40
    static let width = CGFloat(PickerModel.cols) * cell + 24
    static let height: CGFloat = 480
    private static let columns = Array(repeating: GridItem(.fixed(cell), spacing: 0), count: PickerModel.cols)
    /// Scroll id of a section header: same `Pos` type as the cells, at an index no cell uses.
    private static let headerIndex = -1
    private static let icons = [
        "Recently Used": "🕘", "Smileys & Emotion": "😀", "People & Body": "👋", "Animals & Nature": "🐻",
        "Food & Drink": "🍔", "Travel & Places": "✈️", "Activities": "⚽️", "Objects": "💡",
        "Symbols": "🔣", "Flags": "🏁"
    ]

    @Bindable var model: PickerModel
    @FocusState private var focused: Bool

    var body: some View {
        scrollArea
            .frame(width: Self.width, height: Self.height)
            .modifier(PanelBackground())
            .onAppear { focused = true }
            .onChange(of: model.focusToken) { focused = true }
            .onChange(of: model.query) { model.refresh() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Search emoji", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit { pick() }
                .onKeyPress(.upArrow) { model.moveVertically(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.moveVertically(by: 1); return .handled }
                .onKeyPress(.leftArrow) { model.moveHorizontally(by: -1); return .handled }
                .onKeyPress(.rightArrow) { model.moveHorizontally(by: 1); return .handled }
                .onKeyPress(.escape) { model.onDismiss(); return .handled }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .modifier(GlassCapsule())
            Button { model.onSettings() } label: {
                Image(systemName: "gearshape")
                    .frame(width: 40, height: 40)
                    .modifier(GlassCapsule())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding([.horizontal, .top], 10)
    }

    /// The grid fills the panel and scrolls under the floating search bar and footer.
    private var scrollArea: some View {
        ScrollViewReader { proxy in
            grid
                .onChange(of: model.pos) { _, newPos in proxy.scrollTo(newPos) }
                .safeAreaInset(edge: .top, spacing: 0) { searchBar }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.query.isEmpty {  // search results are one flat section: nothing to jump between
                        footer(proxy)
                    }
                }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.sections.enumerated()), id: \.offset) { section, group in
                    Text(group.name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .id(Pos(section: section, index: Self.headerIndex))
                    if group.emojis.isEmpty {
                        Text("No results").foregroundStyle(.secondary).padding(12)
                    }
                    LazyVGrid(columns: Self.columns, spacing: 0) {
                        ForEach(Array(group.emojis.enumerated()), id: \.offset) { index, emoji in
                            cell(emoji, at: Pos(section: section, index: index))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// One button per section. Clicking scrolls its header to the top and moves the selection there.
    private func footer(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(model.sections.enumerated()), id: \.offset) { section, group in
                Button {
                    model.pos = Pos(section: section, index: 0)
                    proxy.scrollTo(Pos(section: section, index: Self.headerIndex), anchor: .top)
                    focused = true
                } label: {
                    Text(Self.icons[group.name] ?? group.emojis.first?.char ?? "•")
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(model.pos.section == section ? Color.accentColor.opacity(0.35) : .clear,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(group.name)
            }
        }
        .padding(4)
        .modifier(GlassCapsule())
        .padding([.horizontal, .bottom], 10)
    }

    private func cell(_ emoji: Emoji, at position: Pos) -> some View {
        Text(emoji.char(tone: model.tone))
            .font(.system(size: 26))
            .frame(width: Self.cell, height: Self.cell)
            .background(model.pos == position ? Color.accentColor.opacity(0.35) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { model.pos = position; pick() }
            .help(emoji.name)
            .id(position)
    }

    private func pick() {
        if let emoji = model.selected { model.onPick(emoji) }
    }
}

// MARK: - Controller

/// One panel, created once and reused: hiding/showing is what keeps it fast.
final class PickerController {
    private let model = PickerModel()
    private let panel: PickerPanel
    /// The menu-bar menu, shared so the picker's settings (gear) button shows the same one.
    var menu: NSMenu?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = PickerPanel(content: NSHostingView(rootView: PickerView(model: model)))
        model.onPick = { [unowned self] emoji in
            hide()
            Recents.add(emoji.char)  // base char: recents follow the current skin tone
            Paste.insert(emoji.char(tone: model.tone))
        }
        model.onDismiss = { [unowned self] in hide() }
        model.onSettings = { [unowned self] in showMenu() }
    }

    private func showMenu() {
        guard let menu else { return }
        panel.keepOpenOnResignKey = true
        // popUp blocks until the menu closes; the chosen item's action has run by then.
        menu.popUp(positioning: nil,
                   at: panel.contentView?.convert(panel.mouseLocationOutsideOfEventStream, from: nil) ?? .zero,
                   in: panel.contentView)
        panel.keepOpenOnResignKey = false
        model.tone = SkinTone.current  // skin tone may have just changed
        if let other = NSApp.keyWindow, other !== panel {
            hide()  // e.g. "Custom…" opened the recorder window
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        model.query = ""
        model.refresh()
        model.focusToken += 1

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                     y: frame.midY - panel.frame.height / 2 + frame.height * 0.1))
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
