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
    var s = 0
    var i = 0
}

@Observable
final class PickerModel {
    static let cols = 9

    var query = ""
    var pos = Pos()
    var focusToken = 0
    private(set) var sections: [Group] = []
    var onPick: (Emoji) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    init() { refresh() }

    var selected: Emoji? {
        guard sections.indices.contains(pos.s), sections[pos.s].emojis.indices.contains(pos.i) else { return nil }
        return sections[pos.s].emojis[pos.i]
    }

    func refresh() {
        pos = Pos()
        if query.isEmpty {
            let recent = Recents.list.compactMap { EmojiStore.byChar[$0] }
            sections = (recent.isEmpty ? [] : [Group(name: "Recently Used", emojis: recent)]) + EmojiStore.groups
        } else {
            sections = [Group(name: "Results", emojis: EmojiStore.search(query))]
        }
    }

    /// Grid navigation across sections. Up/down keep the column; partial last rows clamp.
    func move(dx: Int, dy: Int) {
        let cols = Self.cols
        func count(_ s: Int) -> Int { sections[s].emojis.count }
        guard count(pos.s) > 0 else { return }
        var s = pos.s, i = pos.i

        if dx != 0 {
            i += dx
            if i < 0 {
                if s > 0 { s -= 1; i = count(s) - 1 } else { i = 0 }
            } else if i >= count(s) {
                if s < sections.count - 1 { s += 1; i = 0 } else { i = count(s) - 1 }
            }
        } else {
            let col = i % cols
            i += dy * cols
            if i < 0 {
                if s > 0 {
                    s -= 1
                    i = min((count(s) - 1) / cols * cols + col, count(s) - 1)
                } else { i = pos.i }
            } else if i >= count(s) {
                if pos.i / cols < (count(s) - 1) / cols {
                    i = count(s) - 1
                } else if s < sections.count - 1 {
                    s += 1
                    i = min(col, count(s) - 1)
                } else { i = pos.i }
            }
        }
        pos = Pos(s: s, i: i)
    }
}

// MARK: - View

struct PickerView: View {
    static let cell: CGFloat = 40
    static let width = CGFloat(PickerModel.cols) * cell + 24
    static let height: CGFloat = 460

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
                .onKeyPress(.upArrow) { model.move(dx: 0, dy: -1); return .handled }
                .onKeyPress(.downArrow) { model.move(dx: 0, dy: 1); return .handled }
                .onKeyPress(.leftArrow) { model.move(dx: -1, dy: 0); return .handled }
                .onKeyPress(.rightArrow) { model.move(dx: 1, dy: 0); return .handled }
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
                    ForEach(Array(model.sections.enumerated()), id: \.offset) { s, group in
                        Text(group.name)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        if group.emojis.isEmpty {
                            Text("No results").foregroundStyle(.secondary).padding(12)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 0), count: PickerModel.cols),
                                  spacing: 0) {
                            ForEach(Array(group.emojis.enumerated()), id: \.offset) { i, emoji in
                                let p = Pos(s: s, i: i)
                                Text(emoji.char)
                                    .font(.system(size: 26))
                                    .frame(width: Self.cell, height: Self.cell)
                                    .background(model.pos == p ? Color.accentColor.opacity(0.35) : .clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.pos = p; pick() }
                                    .help(emoji.name)
                                    .id(p)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.pos) { _, p in proxy.scrollTo(p) }
        }
    }

    private func pick() {
        if let e = model.selected { model.onPick(e) }
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
            Recents.add(emoji.char)
            Paste.insert(emoji.char)
        }
        model.onDismiss = { [unowned self] in hide() }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        model.query = ""
        model.refresh()
        model.focusToken += 1

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                     y: f.midY - panel.frame.height / 2 + f.height * 0.1))
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
