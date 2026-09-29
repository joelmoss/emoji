import Testing
@testable import Emoji

/// Sections of `counts` emoji each; the grid is 9 columns wide, so [10, 9, 3] gives
/// a partial last row in section 0 (1 item) and a short single row in section 2.
private func model(_ counts: Int...) -> PickerModel {
    PickerModel(sections: counts.enumerated().map { section, count in
        EmojiGroup(name: "s\(section)", emojis: (0..<count).map { Emoji(char: "\(section)-\($0)", name: "e") })
    })
}

private func position(_ section: Int, _ index: Int) -> Pos { Pos(section: section, index: index) }

struct HorizontalTests {
    @Test(arguments: [
        (position(0, 3), 1, position(0, 4)),
        (position(0, 9), 1, position(1, 0)),   // spill into next section
        (position(1, 0), -1, position(0, 9)),  // spill back into last item
        (position(0, 0), -1, position(0, 0)),  // top-left edge
        (position(2, 2), 1, position(2, 2))    // bottom-right edge
    ])
    func moves(start: Pos, delta: Int, expected: Pos) {
        let picker = model(10, 9, 3)
        picker.pos = start
        picker.moveHorizontally(by: delta)
        #expect(picker.pos == expected)
    }
}

struct VerticalTests {
    @Test(arguments: [
        (position(0, 0), 1, position(0, 9)),   // next row
        (position(0, 1), 1, position(0, 9)),   // partial last row clamps to last item
        (position(0, 9), 1, position(1, 0)),   // last row → next section, same column
        (position(1, 5), 1, position(2, 2)),   // column clamps to short section
        (position(2, 1), 1, position(2, 1)),   // bottom edge
        (position(1, 0), -1, position(0, 9)),  // first row → previous section's last row
        (position(1, 5), -1, position(0, 9)),  // …column clamps to its partial last row
        (position(2, 2), -1, position(1, 2)),
        (position(0, 3), -1, position(0, 3))   // top edge
    ])
    func moves(start: Pos, delta: Int, expected: Pos) {
        let picker = model(10, 9, 3)
        picker.pos = start
        picker.moveVertically(by: delta)
        #expect(picker.pos == expected)
    }
}

struct EmptyResultsTests {
    @Test func movesAreNoOps() {
        let picker = model(0)
        picker.moveHorizontally(by: 1)
        picker.moveVertically(by: 1)
        picker.moveVertically(by: -1)
        #expect(picker.pos == Pos())
        #expect(picker.selected == nil)
    }
}
