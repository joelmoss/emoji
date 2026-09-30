import AppKit
import Testing
@testable import Emoji

/// All tests use a private named pasteboard, never the user's real clipboard.
private func scratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("com.joelmoss.emoji.tests.\(UUID().uuidString)"))
}

struct PasteTests {
    @Test func restoreBringsTheOldClipboardBack() {
        let board = scratchPasteboard()
        Paste.write("before", to: board, transient: false)
        let saved = Paste.snapshot(board)

        let stamp = Paste.write("😀", to: board, transient: true)
        Paste.restore(saved, to: board, unlessChangedSince: stamp)

        #expect(board.string(forType: .string) == "before")
    }

    @Test func restoreLeavesACopyMadeInTheMeantimeAlone() {
        let board = scratchPasteboard()
        Paste.write("before", to: board, transient: false)
        let saved = Paste.snapshot(board)

        let stamp = Paste.write("😀", to: board, transient: true)
        Paste.write("copied by the user mid-paste", to: board, transient: false)
        Paste.restore(saved, to: board, unlessChangedSince: stamp)

        #expect(board.string(forType: .string) == "copied by the user mid-paste")
    }

    @Test func pickedEmojiIsMarkedTransientForClipboardManagers() {
        let board = scratchPasteboard()
        Paste.write("😀", to: board, transient: true)
        #expect(board.types?.contains(Paste.transientType) == true)
        #expect(board.string(forType: .string) == "😀")

        Paste.write("😀", to: board, transient: false)
        #expect(board.types?.contains(Paste.transientType) != true)
    }

    @Test func restoringAnEmptyClipboardEmptiesIt() {
        let board = scratchPasteboard()
        board.clearContents()
        let saved = Paste.snapshot(board)

        let stamp = Paste.write("😀", to: board, transient: true)
        Paste.restore(saved, to: board, unlessChangedSince: stamp)

        #expect(board.string(forType: .string) == nil)
    }
}
