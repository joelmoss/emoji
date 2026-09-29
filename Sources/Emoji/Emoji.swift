import Foundation

struct Emoji: Decodable {
    let char: String
    let name: String

    enum CodingKeys: String, CodingKey { case char = "c", name = "n" }
}

struct Group: Decodable {
    let name: String
    let emojis: [Emoji]
}

enum EmojiStore {
    static let groups: [Group] = {
        // Bundle.main: .app build (bundle.sh). Bundle.module: `swift run`.
        let url = Bundle.main.url(forResource: "emojis", withExtension: "json")
            ?? Bundle.module.url(forResource: "emojis", withExtension: "json")!
        return try! JSONDecoder().decode([Group].self, from: Data(contentsOf: url))
    }()

    static let all = groups.flatMap(\.emojis)
    static let byChar = Dictionary(uniqueKeysWithValues: all.map { ($0.char, $0) })

    static func search(_ query: String) -> [Emoji] {
        let words = query.lowercased().split(separator: " ")
        return all.filter { e in words.allSatisfy { e.name.contains($0) } }
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
