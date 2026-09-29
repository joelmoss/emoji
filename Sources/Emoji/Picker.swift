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

    // Click-away close. Non-activating means the app never becomes active,
    // so hidesOnDeactivate / applicationDidResignActive would never fire.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
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

struct PickerView: View {
    static let cell: CGFloat = 40
    static let width = CGFloat(PickerModel.cols) * cell + 24
    static let height: CGFloat = 460
    private static let columns = Array(repeating: GridItem(.fixed(cell), spacing: 0), count: PickerModel.cols)

    @Bindable var model: PickerModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search emoji", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($focused)
                .onSubmit { pick() }
                .onKeyPress(.upArrow) { model.moveVertically(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.moveVertically(by: 1); return .handled }
                .onKeyPress(.leftArrow) { model.moveHorizontally(by: -1); return .handled }
                .onKeyPress(.rightArrow) { model.moveHorizontally(by: 1); return .handled }
                .onKeyPress(.escape) { model.onDismiss(); return .handled }
            Divider()
            grid
        }
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
        .onChange(of: model.query) { model.refresh() }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.sections.enumerated()), id: \.offset) { section, group in
                        Text(group.name)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
            .onChange(of: model.pos) { _, newPos in proxy.scrollTo(newPos) }
        }
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

    init() {
        panel = PickerPanel(content: NSHostingView(rootView: PickerView(model: model)))
        model.onPick = { [unowned self] emoji in
            hide()
            Recents.add(emoji.char)  // base char: recents follow the current skin tone
            Paste.insert(emoji.char(tone: model.tone))
        }
        model.onDismiss = { [unowned self] in hide() }
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
