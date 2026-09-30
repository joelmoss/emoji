import Testing
@testable import Emoji

struct EmojiDataTests {
    @Test func loadsAllGroups() {
        #expect(EmojiStore.groups.first?.name == "Smileys & Emotion")
        #expect(EmojiStore.all.count > 1800)
    }

    @Test(arguments: [
        ("happy", "😀"),            // CLDR keyword, not in the name
        ("grinning face", "😀"),    // multi-word, all words must match
        ("smil", "😀"),             // word prefix
        ("SAO tome", "🇸🇹"),         // case + diacritics folded
        ("thumb", "👍")
    ])
    func searchFinds(query: String, expected: String) {
        #expect(EmojiStore.search(query).contains { $0.char == expected })
    }

    @Test func searchMatchesWordStartsOnly() {
        // Emoji whose only "hat" is inside a longer word (e.g. "that", "chat") must not match.
        let midWordOnly = EmojiStore.all.filter { $0.haystack.contains("hat") && !$0.haystack.contains(" hat") }
        #expect(!midWordOnly.isEmpty)  // guard: the data really has such emoji, so this test can fail

        let results = EmojiStore.search("hat")
        #expect(results.contains { $0.char == "🎩" })
        #expect(!results.contains { hit in midWordOnly.contains { $0.char == hit.char } })
    }

    @Test func searchMissReturnsNothing() {
        #expect(EmojiStore.search("zzzzqqq").isEmpty)
    }

    @Test func skinTones() throws {
        let thumbsUp = try #require(EmojiStore.byChar["👍"])
        #expect(thumbsUp.tones?.count == 5)
        #expect(thumbsUp.char(tone: 0) == "👍")
        #expect(thumbsUp.char(tone: 3) == "👍🏽")

        let grinning = try #require(EmojiStore.byChar["😀"])
        #expect(grinning.tones == nil)
        #expect(grinning.char(tone: 3) == "😀")  // no variants: falls back to the base
    }

    @Test func outOfRangeToneFallsBackToBase() throws {
        // A stale or hand-edited saved preference must never index past the five variants.
        let thumbsUp = try #require(EmojiStore.byChar["👍"])
        #expect(thumbsUp.char(tone: 6) == "👍")
        #expect(thumbsUp.char(tone: -1) == "👍")
    }

    @Test func skinToneSamples() {
        #expect(SkinTone.sample(0) == "👍")
        #expect(SkinTone.sample(1) == "👍🏻")
        #expect(SkinTone.sample(5) == "👍🏿")
    }
}

struct PickerQueryTests {
    @Test func blankQueryShowsCategoriesNotAFlatResultList() {
        let picker = PickerModel()
        picker.query = "   "
        picker.refresh()
        #expect(picker.sections.count > 1)
        #expect(picker.sections.allSatisfy { $0.name != "Results" })
        #expect(!picker.isSearching)
        picker.query = " happy "
        picker.refresh()
        #expect(picker.isSearching)
        #expect(picker.sections.map(\.name) == ["Results"])
    }
}
