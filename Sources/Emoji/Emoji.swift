import Foundation

struct Emoji: Decodable {
    let char: String
    let name: String
    /// Five uniform skin-tone variants (light … dark), when the emoji has them.
    let tones: [String]?
    /// " " + search words. Word-prefix match is `haystack.contains(" " + query)`.
    let haystack: String

    enum CodingKeys: String, CodingKey { case char = "c", name = "n", tones = "t", words = "k" }

    init(char: String, name: String, tones: [String]? = nil, words: String = "") {
        self.char = char
        self.name = name
        self.tones = tones
        haystack = " " + words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(char: try container.decode(String.self, forKey: .char),
                  name: try container.decode(String.self, forKey: .name),
                  tones: try container.decodeIfPresent([String].self, forKey: .tones),
                  words: try container.decode(String.self, forKey: .words))
    }

    /// `tone` 0 is the default; 1…5 picks a skin-tone variant when one exists.
    func char(tone: Int) -> String {
        guard tone > 0, let tones else { return char }
        return tones[tone - 1]
    }
}

struct EmojiGroup: Decodable {
    let name: String
    let emojis: [Emoji]
}

enum EmojiStore {
    static let groups: [EmojiGroup] = {
        // Bundle.main: .app build (bundle.sh). Bundle.module: `swift run` and tests.
        let url = Bundle.main.url(forResource: "emojis", withExtension: "json")
            ?? Bundle.module.url(forResource: "emojis", withExtension: "json")!
        do {
            return try JSONDecoder().decode([EmojiGroup].self, from: Data(contentsOf: url))
        } catch {
            fatalError("Cannot load emojis.json: \(error)")
        }
    }()

    static let all = groups.flatMap(\.emojis)
    static let byChar = Dictionary(uniqueKeysWithValues: all.map { ($0.char, $0) })

    /// Every query word must prefix some word of the emoji's name or CLDR keywords.
    static func search(_ query: String) -> [Emoji] {
        let words = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(separator: " ").map { " " + $0 }
        return all.filter { emoji in words.allSatisfy { emoji.haystack.contains($0) } }
    }
}

enum Recents {
    private static let key = "recents"

    static var list: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ char: String) {
        let updated = [char] + list.filter { $0 != char }
        UserDefaults.standard.set(Array(updated.prefix(27)), forKey: key)  // 3 rows
    }
}

enum SkinTone {
    static let key = "skinTone"
    static let names = ["Default", "Light", "Medium-Light", "Medium", "Medium-Dark", "Dark"]

    static var current: Int { UserDefaults.standard.integer(forKey: key) }

    static func sample(_ tone: Int) -> String {
        tone == 0 ? "👍" : "👍" + String(Unicode.Scalar(UInt32(0x1F3FA + tone))!)
    }
}
